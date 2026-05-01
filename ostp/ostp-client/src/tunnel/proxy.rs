use std::net::{IpAddr, Ipv4Addr};
use std::collections::HashMap;

use anyhow::{anyhow, Context, Result};
use tokio::io::{AsyncReadExt, AsyncWriteExt};
use tokio::net::{TcpListener, TcpStream};
use tokio::sync::{mpsc, watch};

use crate::config::{LocalProxyConfig, OstpConfig};
use crate::tunnel::{ProxyEvent, ProxyToClientMsg};

pub async fn run_local_socks5_proxy(
    cfg: LocalProxyConfig,
    ostp: OstpConfig,
    mut shutdown: watch::Receiver<bool>,
    proxy_events_tx: mpsc::Sender<ProxyEvent>,
    mut client_msgs_rx: mpsc::Receiver<(u16, ProxyToClientMsg)>,
) -> Result<()> {
    let listener = TcpListener::bind(&cfg.bind_addr)
        .await
        .with_context(|| format!("failed to bind local proxy at {}", cfg.bind_addr))?;

    eprintln!("[ostp-client] local SOCKS5 proxy listening at {}", cfg.bind_addr);

    let (connect_tx, mut connect_rx) = mpsc::channel(128);

    let mut next_stream_id: u16 = 1;
    let mut active_streams: HashMap<u16, mpsc::Sender<ProxyToClientMsg>> = HashMap::new();

    loop {
        tokio::select! {
            _ = shutdown.changed() => {
                if *shutdown.borrow() {
                    break;
                }
            }
            accepted = listener.accept() => {
                let (socket, _) = accepted?;
                let stream_id = next_stream_id;
                next_stream_id = next_stream_id.wrapping_add(1);
                if next_stream_id == 0 { next_stream_id = 1; }

                let (tx, rx) = mpsc::channel(256);
                active_streams.insert(stream_id, tx);

                let event_tx = proxy_events_tx.clone();
                let c_tx = connect_tx.clone();
                tokio::spawn(async move {
                    if let Err(err) = handle_socks5_client(socket, stream_id, event_tx, rx, c_tx).await {
                        eprintln!("[ostp-client] proxy client error: {err}");
                    }
                });
            }
            Some((stream_id, msg)) = client_msgs_rx.recv() => {
                if let Some(tx) = active_streams.get(&stream_id) {
                    if tx.send(msg).await.is_err() {
                        active_streams.remove(&stream_id);
                    }
                }
            }
            Some(stream_id) = connect_rx.recv() => {
                active_streams.remove(&stream_id);
            }
        }
    }

    Ok(())
}

async fn handle_socks5_client(
    mut client: TcpStream,
    stream_id: u16,
    event_tx: mpsc::Sender<ProxyEvent>,
    mut rx: mpsc::Receiver<ProxyToClientMsg>,
    close_tx: mpsc::Sender<u16>,
) -> Result<()> {
    let mut greeting = [0_u8; 2];
    client.read_exact(&mut greeting).await?;
    if greeting[0] != 0x05 {
        return Err(anyhow!("unsupported socks version"));
    }

    let methods_count = greeting[1] as usize;
    let mut methods = vec![0_u8; methods_count];
    client.read_exact(&mut methods).await?;

    if !methods.contains(&0x00) {
        client.write_all(&[0x05, 0xff]).await?;
        return Err(anyhow!("client does not support no-auth socks5"));
    }

    client.write_all(&[0x05, 0x00]).await?;

    let mut req = [0_u8; 4];
    client.read_exact(&mut req).await?;

    if req[0] != 0x05 { return Err(anyhow!("invalid socks request version")); }
    if req[1] != 0x01 {
        send_socks_reply(&mut client, 0x07).await?;
        return Err(anyhow!("unsupported socks command"));
    }

    let target_host = read_target_host(&mut client, req[3]).await?;
    let mut port_bytes = [0_u8; 2];
    client.read_exact(&mut port_bytes).await?;
    let target_port = u16::from_be_bytes(port_bytes);
    let target = format!("{target_host}:{target_port}");

    event_tx.send(ProxyEvent::NewStream { stream_id, target }).await?;

    // Wait for ConnectOk
    match rx.recv().await {
        Some(ProxyToClientMsg::ConnectOk) => {
            send_socks_reply(&mut client, 0x00).await?;
        }
        Some(ProxyToClientMsg::Error(msg)) => {
            send_socks_reply(&mut client, 0x05).await?;
            let _ = close_tx.send(stream_id).await;
            return Err(anyhow!("connect error: {msg}"));
        }
        _ => {
            send_socks_reply(&mut client, 0x04).await?;
            let _ = close_tx.send(stream_id).await;
            return Err(anyhow!("connect dropped"));
        }
    }

    let mut tcp_buf = vec![0_u8; 8192];
    loop {
        tokio::select! {
            read_res = client.read(&mut tcp_buf) => {
                match read_res {
                    Ok(0) => {
                        let _ = event_tx.send(ProxyEvent::Close { stream_id }).await;
                        break;
                    }
                    Ok(n) => {
                        let _ = event_tx.send(ProxyEvent::Data { stream_id, payload: bytes::Bytes::copy_from_slice(&tcp_buf[..n]) }).await;
                    }
                    Err(_) => {
                        let _ = event_tx.send(ProxyEvent::Close { stream_id }).await;
                        break;
                    }
                }
            }
            msg = rx.recv() => {
                match msg {
                    Some(ProxyToClientMsg::Data(data)) => {
                        if client.write_all(&data).await.is_err() {
                            let _ = event_tx.send(ProxyEvent::Close { stream_id }).await;
                            break;
                        }
                    }
                    Some(ProxyToClientMsg::Close) | Some(ProxyToClientMsg::Error(_)) | None => {
                        break;
                    }
                    _ => {}
                }
            }
        }
    }

    let _ = close_tx.send(stream_id).await;
    Ok(())
}

async fn read_target_host(client: &mut TcpStream, atyp: u8) -> Result<String> {
    match atyp {
        0x01 => {
            let mut ipv4 = [0_u8; 4];
            client.read_exact(&mut ipv4).await?;
            Ok(IpAddr::V4(Ipv4Addr::from(ipv4)).to_string())
        }
        0x03 => {
            let mut len = [0_u8; 1];
            client.read_exact(&mut len).await?;
            let mut domain = vec![0_u8; len[0] as usize];
            client.read_exact(&mut domain).await?;
            String::from_utf8(domain).context("invalid utf8 in socks domain")
        }
        0x04 => {
            let mut ipv6 = [0_u8; 16];
            client.read_exact(&mut ipv6).await?;
            Ok(IpAddr::from(ipv6).to_string())
        }
        _ => Err(anyhow!("unsupported socks address type")),
    }
}

async fn send_socks_reply(client: &mut TcpStream, rep: u8) -> Result<()> {
    let response = [0x05, rep, 0x00, 0x01, 0, 0, 0, 0, 0, 0];
    client.write_all(&response).await?;
    Ok(())
}
