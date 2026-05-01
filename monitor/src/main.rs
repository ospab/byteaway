mod api;

use ratatui::{
    backend::CrosstermBackend,
    layout::{Alignment, Constraint, Direction, Layout, Rect},
    style::{Color, Modifier, Style},
    text::{Line, Span},
    widgets::{Block, Paragraph, Row, Table, Wrap},
    Frame, Terminal,
};
use crossterm::{
    event::{self, DisableMouseCapture, EnableMouseCapture, Event, KeyCode},
    execute,
    terminal::{disable_raw_mode, enable_raw_mode, EnterAlternateScreen, LeaveAlternateScreen},
};
use std::io;
use std::sync::Arc;
use std::time::Duration;
use tokio::sync::Mutex;
use tokio::time::interval;
use api::{ApiClient, SystemStats, ClientInfo, DeviceInfo};

#[derive(Clone, PartialEq)]
enum Tab {
    Stats,
    Clients,
    Devices,
}

struct AppState {
    api_client: ApiClient,
    current_tab: Tab,
    stats: Option<SystemStats>,
    clients: Option<Vec<ClientInfo>>,
    devices: Option<Vec<DeviceInfo>>,
    selected_index: usize,
    last_update: String,
}

impl AppState {
    fn new(api_client: ApiClient) -> Self {
        Self {
            api_client,
            current_tab: Tab::Stats,
            stats: None,
            clients: None,
            devices: None,
            selected_index: 0,
            last_update: "Never".to_string(),
        }
    }

    async fn refresh_data(&mut self) {
        let now = chrono::Local::now().format("%H:%M:%S").to_string();
        
        match self.api_client.get_system_stats().await {
            Ok(stats) => self.stats = Some(stats),
            Err(e) => eprintln!("Failed to fetch stats: {}", e),
        }

        match self.api_client.list_clients().await {
            Ok(clients) => self.clients = Some(clients),
            Err(e) => eprintln!("Failed to fetch clients: {}", e),
        }

        match self.api_client.list_devices().await {
            Ok(devices) => self.devices = Some(devices),
            Err(e) => eprintln!("Failed to fetch devices: {}", e),
        }

        self.last_update = now;
    }
}

fn draw_stats(f: &mut Frame, app: &AppState, area: Rect) {
    let stats = match &app.stats {
        Some(s) => s,
        None => {
            let text = Paragraph::new("Loading...")
                .block(Block::bordered().title("System Statistics"))
                .style(Style::default().fg(Color::Gray));
            f.render_widget(text, area);
            return;
        }
    };

    let stats_text = vec![
        Line::from(vec![
            Span::styled("Total Clients: ", Style::default().fg(Color::Cyan)),
            Span::styled(stats.total_clients.to_string(), Style::default().fg(Color::White).add_modifier(Modifier::BOLD)),
        ]),
        Line::from(vec![
            Span::styled("Active Devices: ", Style::default().fg(Color::Cyan)),
            Span::styled(stats.active_devices.to_string(), Style::default().fg(Color::Green).add_modifier(Modifier::BOLD)),
        ]),
        Line::from(vec![
            Span::styled("Total Traffic: ", Style::default().fg(Color::Cyan)),
            Span::styled(format!("{} GB", stats.total_traffic_gb), Style::default().fg(Color::Yellow).add_modifier(Modifier::BOLD)),
        ]),
        Line::from(vec![
            Span::styled("Total Balance: ", Style::default().fg(Color::Cyan)),
            Span::styled(format!("${}", stats.total_balance_usd), Style::default().fg(Color::Green).add_modifier(Modifier::BOLD)),
        ]),
        Line::from(vec![
            Span::styled("Active Sessions: ", Style::default().fg(Color::Cyan)),
            Span::styled(stats.active_sessions.to_string(), Style::default().fg(Color::Blue).add_modifier(Modifier::BOLD)),
        ]),
    ];

    let paragraph = Paragraph::new(stats_text)
        .block(Block::bordered().title("System Statistics"))
        .style(Style::default().fg(Color::White))
        .wrap(Wrap { trim: true });
    f.render_widget(paragraph, area);
}

fn draw_clients(f: &mut Frame, app: &AppState, area: Rect) {
    let clients = match &app.clients {
        Some(c) => c,
        None => {
            let text = Paragraph::new("Loading...")
                .block(Block::bordered().title("Clients"))
                .style(Style::default().fg(Color::Gray));
            f.render_widget(text, area);
            return;
        }
    };

    let rows: Vec<Row> = clients.iter().map(|c| {
        Row::new(vec![
            c.id.to_string().chars().take(8).collect::<String>(),
            c.email.clone(),
            format!("${}", c.balance_usd),
            c.device_count.to_string(),
        ])
    }).collect();

    let header = Row::new(vec!["ID", "Email", "Balance", "Devices"])
        .style(Style::default().fg(Color::Cyan).add_modifier(Modifier::BOLD));

    let table = Table::new(rows, &[Constraint::Percentage(15), Constraint::Percentage(45), Constraint::Percentage(20), Constraint::Percentage(20)])
        .header(header)
        .block(Block::bordered().title("Clients"))
        .style(Style::default().fg(Color::White));
    f.render_widget(table, area);
}

fn draw_devices(f: &mut Frame, app: &AppState, area: Rect) {
    let devices = match &app.devices {
        Some(d) => d,
        None => {
            let text = Paragraph::new("Loading...")
                .block(Block::bordered().title("Devices"))
                .style(Style::default().fg(Color::Gray));
            f.render_widget(text, area);
            return;
        }
    };

    let rows: Vec<Row> = devices.iter().enumerate().map(|(i, d)| {
        let style = if i == app.selected_index {
            Style::default().fg(Color::Yellow).add_modifier(Modifier::BOLD)
        } else {
            Style::default()
        };

        let status = if d.is_blocked {
            "BLOCKED".to_string()
        } else if d.is_active {
            "ACTIVE".to_string()
        } else {
            "INACTIVE".to_string()
        };

        Row::new(vec![
            d.id.to_string().chars().take(8).collect::<String>(),
            d.hwid.chars().take(12).collect::<String>(),
            d.vless_uuid.chars().take(8).collect::<String>(),
            d.os_type.as_deref().unwrap_or("Unknown").to_string(),
            status,
        ]).style(style)
    }).collect();

    let header = Row::new(vec!["ID", "HWID", "VLESS UUID", "OS", "Status"])
        .style(Style::default().fg(Color::Cyan).add_modifier(Modifier::BOLD));

    let table = Table::new(rows, &[Constraint::Percentage(15), Constraint::Percentage(25), Constraint::Percentage(20), Constraint::Percentage(15), Constraint::Percentage(25)])
        .header(header)
        .block(Block::bordered().title("Devices (Press 'b' to block, 'u' to unblock)"))
        .style(Style::default().fg(Color::White));
    f.render_widget(table, area);
}

fn draw_ui(f: &mut Frame, app: &AppState) {
    let chunks = Layout::default()
        .direction(Direction::Vertical)
        .margin(1)
        .constraints([
            Constraint::Length(3),
            Constraint::Min(0),
            Constraint::Length(1),
        ])
        .split(f.size());

    let header_text = vec![
        Line::from(vec![
            Span::styled("ByteAway Monitor", Style::default().fg(Color::Cyan).add_modifier(Modifier::BOLD)),
            Span::raw(" | "),
            Span::styled("Last Update: ", Style::default().fg(Color::Gray)),
            Span::styled(&app.last_update, Style::default().fg(Color::Green)),
        ]),
    ];

    let header = Paragraph::new(header_text)
        .alignment(Alignment::Center)
        .block(Block::bordered());
    f.render_widget(header, chunks[0]);

    let tab_names = vec!["Stats", "Clients", "Devices"];
    let tabs: Vec<Line> = tab_names.iter().map(|&name| {
        let is_selected = match (name, &app.current_tab) {
            ("Stats", Tab::Stats) => true,
            ("Clients", Tab::Clients) => true,
            ("Devices", Tab::Devices) => true,
            _ => false,
        };
        
        if is_selected {
            Line::from(vec![
                Span::styled("[", Style::default().fg(Color::Gray)),
                Span::styled(name, Style::default().fg(Color::Cyan).add_modifier(Modifier::BOLD)),
                Span::styled("]", Style::default().fg(Color::Gray)),
            ])
        } else {
            Line::from(vec![
                Span::styled(" ", Style::default()),
                Span::styled(name, Style::default().fg(Color::Gray)),
                Span::styled(" ", Style::default()),
            ])
        }
    }).collect();

    let tabs_paragraph = Paragraph::new(tabs.clone())
        .alignment(Alignment::Center)
        .block(Block::bordered().title("Tabs (1-3 to switch)"));
    f.render_widget(tabs_paragraph, chunks[1]);

    let content_area = Layout::default()
        .direction(Direction::Vertical)
        .constraints([Constraint::Length(3), Constraint::Min(0)])
        .split(chunks[1]);

    let tabs_paragraph = Paragraph::new(tabs)
        .alignment(Alignment::Center);
    f.render_widget(tabs_paragraph, content_area[0]);

    match app.current_tab {
        Tab::Stats => draw_stats(f, app, content_area[1]),
        Tab::Clients => draw_clients(f, app, content_area[1]),
        Tab::Devices => draw_devices(f, app, content_area[1]),
    }

    let footer = Paragraph::new("Press 'q' to quit | Arrow keys to navigate")
        .style(Style::default().fg(Color::Gray))
        .alignment(Alignment::Center);
    f.render_widget(footer, chunks[2]);
}

#[tokio::main]
async fn main() -> anyhow::Result<()> {
    let args: Vec<String> = std::env::args().collect();
    
    if args.len() < 3 {
        eprintln!("Usage: {} <api_url> <admin_key>", args[0]);
        eprintln!("Example: {} http://localhost:3000 your-secret-key", args[0]);
        std::process::exit(1);
    }

    let api_url = args[1].clone();
    let admin_key = args[2].clone();

    let api_client = ApiClient::new(api_url, admin_key);
    let app_state = Arc::new(Mutex::new(AppState::new(api_client)));

    enable_raw_mode()?;
    let mut stdout = io::stdout();
    execute!(stdout, EnterAlternateScreen, EnableMouseCapture)?;
    let backend = CrosstermBackend::new(stdout);
    let mut terminal = Terminal::new(backend)?;

    let app_state_clone = app_state.clone();
    tokio::spawn(async move {
        let mut interval = interval(Duration::from_secs(5));
        loop {
            interval.tick().await;
            let api_client = {
                let state = app_state_clone.lock().await;
                state.api_client.clone()
            };
            
            let now = chrono::Local::now().format("%H:%M:%S").to_string();
            
            let stats = api_client.get_system_stats().await.ok();
            let clients = api_client.list_clients().await.ok();
            let devices = api_client.list_devices().await.ok();

            let mut state = app_state_clone.lock().await;
            if let Some(s) = stats {
                state.stats = Some(s);
            }
            if let Some(c) = clients {
                state.clients = Some(c);
            }
            if let Some(d) = devices {
                state.devices = Some(d);
            }
            state.last_update = now;
        }
    });

    let mut state = app_state.lock().await;
    state.refresh_data().await;
    drop(state);

    let result = run_app(&mut terminal, app_state.clone()).await;

    disable_raw_mode()?;
    execute!(
        terminal.backend_mut(),
        LeaveAlternateScreen,
        DisableMouseCapture
    )?;
    terminal.show_cursor()?;

    result
}

async fn run_app<B: ratatui::backend::Backend>(
    terminal: &mut Terminal<B>,
    app_state: Arc<Mutex<AppState>>,
) -> anyhow::Result<()> {
    loop {
        let state = app_state.lock().await;
        let state_clone = AppState {
            api_client: state.api_client.clone(),
            current_tab: state.current_tab.clone(),
            stats: state.stats.clone(),
            clients: state.clients.clone(),
            devices: state.devices.clone(),
            selected_index: state.selected_index,
            last_update: state.last_update.clone(),
        };
        drop(state);

        terminal.draw(|f| {
            draw_ui(f, &state_clone);
        })?;

        if event::poll(Duration::from_millis(100))? {
            if let Event::Key(key) = event::read()? {
                let mut state = app_state.lock().await;
                
                match key.code {
                    KeyCode::Char('q') => return Ok(()),
                    KeyCode::Char('1') => state.current_tab = Tab::Stats,
                    KeyCode::Char('2') => state.current_tab = Tab::Clients,
                    KeyCode::Char('3') => state.current_tab = Tab::Devices,
                    KeyCode::Up => {
                        if state.selected_index > 0 {
                            state.selected_index -= 1;
                        }
                    }
                    KeyCode::Down => {
                        if let Some(devices) = &state.devices {
                            if state.selected_index < devices.len().saturating_sub(1) {
                                state.selected_index += 1;
                            }
                        }
                    }
                    _ => {}
                }
            }
        }
    }
}

