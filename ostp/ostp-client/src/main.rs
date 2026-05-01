mod app;
mod bridge;
mod config;
mod signal;
mod sysproxy;
mod tui;
mod tunnel;

use anyhow::Result;
use tokio::sync::{mpsc, watch};

use crate::app::BridgeCommand;
use crate::bridge::Bridge;
use crate::config::ClientConfig;
use crate::signal::wait_for_shutdown_signal;
use crate::tui::{TuiExit, TuiRuntime};
use std::sync::Arc;

#[cfg(target_os = "windows")]
extern "system" {
    fn FreeConsole() -> i32;
    fn GetConsoleWindow() -> *mut std::ffi::c_void;
    fn ShowWindow(hwnd: *mut std::ffi::c_void, cmd_show: i32) -> i32;
}

fn hide_console() {
    #[cfg(target_os = "windows")]
    unsafe {
        let hwnd = GetConsoleWindow();
        if !hwnd.is_null() {
            ShowWindow(hwnd, 0); // SW_HIDE = 0
        }
        FreeConsole();
    }
}

#[tokio::main]
async fn main() -> Result<()> {
    let no_tui = std::env::args().any(|a| a == "--no-tui");
    let bg = std::env::args().any(|a| a == "--bg");

    if bg {
        hide_console();
    }

    let config = ClientConfig::load_or_create_near_binary()?;

    let (proxy_events_tx, proxy_events_rx) = mpsc::channel(512);
    let (client_msgs_tx, client_msgs_rx) = mpsc::channel(512);

    let metrics = Arc::new(bridge::BridgeMetrics {
        bytes_sent: std::sync::atomic::AtomicU64::new(0),
        bytes_recv: std::sync::atomic::AtomicU64::new(0),
    });

    let bridge = Bridge::new(&config, metrics)?;
    let tui = TuiRuntime::new(config.clone());

    let (ui_tx, ui_rx) = mpsc::channel(512);
    let (cmd_tx, cmd_rx) = mpsc::channel(128);
    let (shutdown_tx, shutdown_rx) = watch::channel(false);
    let proxy_shutdown_rx = shutdown_tx.subscribe();

    let mut ui_rx_opt = Some(ui_rx);

    if bg || no_tui {
        let _ = cmd_tx.send(BridgeCommand::ToggleTunnel).await;
        
        if let Some(mut rx) = ui_rx_opt.take() {
            tokio::spawn(async move {
                while let Some(msg) = rx.recv().await {
                    if let crate::app::UiEvent::Log(text) = msg {
                        println!("[bridge log] {}", text);
                    }
                }
            });
        }
    }

    let bridge_task = tokio::spawn(async move { bridge.run(ui_tx, cmd_rx, shutdown_rx, proxy_events_rx, client_msgs_tx).await });
    let proxy_task = tokio::spawn(async move {
        tunnel::run_local_proxy(config.local_proxy, config.ostp, proxy_shutdown_rx, proxy_events_tx, client_msgs_rx).await
    });
    let signal_cmd_tx = cmd_tx.clone();

    let mut tui_task = if let Some(rx) = ui_rx_opt {
        Some(tokio::spawn(async move { tui.run(rx, cmd_tx).await }))
    } else {
        None
    };
    let mut signal_task = tokio::spawn(async move {
        wait_for_shutdown_signal().await?;
        let _ = signal_cmd_tx.send(BridgeCommand::Shutdown).await;
        Ok::<(), anyhow::Error>(())
    });

    if let Some(task) = &mut tui_task {
        tokio::select! {
            res = task => {
                match res?? {
                    TuiExit::Exit => {}
                    TuiExit::Background => {
                        let _ = signal_task.await?;
                    }
                }
            }
            res = &mut signal_task => {
                res??;
            }
        }
    } else {
        signal_task.await??;
    }

    if let Some(task) = &mut tui_task {
        if !task.is_finished() {
            task.abort();
        }
    }

    let _ = shutdown_tx.send(true);
    let _ = bridge_task.await?;
    let _ = proxy_task.await?;
    tunnel::cleanup().await?;

    Ok(())
}
