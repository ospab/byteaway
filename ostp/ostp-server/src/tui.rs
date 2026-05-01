use std::collections::{HashMap, VecDeque};
use std::io;
use std::net::IpAddr;
use std::time::{Duration, Instant};

use anyhow::Result;
use crossterm::event::{self, Event, KeyCode, KeyEventKind};
use crossterm::execute;
use crossterm::terminal::{disable_raw_mode, enable_raw_mode, EnterAlternateScreen, LeaveAlternateScreen};
use ratatui::backend::CrosstermBackend;
use ratatui::layout::{Constraint, Direction, Layout};
use ratatui::style::{Color, Style};
use ratatui::text::{Line, Span};
use ratatui::widgets::{Block, Borders, Paragraph};
use ratatui::Terminal;
use tokio::sync::mpsc;

#[derive(Debug, Clone)]
pub enum UiCommand {
    CreateClientKey,
    Shutdown,
}

#[derive(Debug, Clone)]
pub enum UiEvent {
    PeerSeen { peer: IpAddr },
    Rx { peer: IpAddr, bytes: usize },
    Tx { peer: IpAddr, bytes: usize },
    UnauthorizedProbe { peer: IpAddr, bytes: usize },
    KeyCreated { key: String },
    Log(String),
    KeyCount(usize),
}

#[derive(Default)]
struct PeerStat {
    rx_total: u64,
    tx_total: u64,
    last_seen: Option<Instant>,
}

struct UiState {
    peers: HashMap<IpAddr, PeerStat>,
    logs: VecDeque<String>,
    key_count: usize,
    total_rx: u64,
    total_tx: u64,
    sample_rx: u64,
    sample_tx: u64,
    rx_bps: u64,
    tx_bps: u64,
    unauthorized_packets: u64,
    last_rate_sample: Instant,
}

impl UiState {
    fn new(initial_key_count: usize) -> Self {
        Self {
            peers: HashMap::new(),
            logs: VecDeque::new(),
            key_count: initial_key_count,
            total_rx: 0,
            total_tx: 0,
            sample_rx: 0,
            sample_tx: 0,
            rx_bps: 0,
            tx_bps: 0,
            unauthorized_packets: 0,
            last_rate_sample: Instant::now(),
        }
    }

    fn log(&mut self, line: String) {
        if self.logs.len() >= 300 {
            self.logs.pop_front();
        }
        self.logs.push_back(line);
    }

    fn apply(&mut self, event: UiEvent) {
        match event {
            UiEvent::PeerSeen { peer } => {
                let entry = self.peers.entry(peer).or_default();
                entry.last_seen = Some(Instant::now());
            }
            UiEvent::Rx { peer, bytes } => {
                let entry = self.peers.entry(peer).or_default();
                entry.rx_total = entry.rx_total.saturating_add(bytes as u64);
                entry.last_seen = Some(Instant::now());
                self.total_rx = self.total_rx.saturating_add(bytes as u64);
            }
            UiEvent::Tx { peer, bytes } => {
                let entry = self.peers.entry(peer).or_default();
                entry.tx_total = entry.tx_total.saturating_add(bytes as u64);
                entry.last_seen = Some(Instant::now());
                self.total_tx = self.total_tx.saturating_add(bytes as u64);
            }
            UiEvent::UnauthorizedProbe { peer, bytes } => {
                self.unauthorized_packets = self.unauthorized_packets.saturating_add(1);
                self.log(format!("Unauthorized packet from {} ({} bytes)", peer, bytes));
            }
            UiEvent::KeyCreated { key } => {
                self.key_count = self.key_count.saturating_add(1);
                self.log(format!("New client key generated: {}", key));
            }
            UiEvent::Log(line) => self.log(line),
            UiEvent::KeyCount(count) => self.key_count = count,
        }
    }

    fn tick(&mut self) {
        let now = Instant::now();
        let dt = now.duration_since(self.last_rate_sample).as_secs_f64();
        if dt >= 1.0 {
            let rx_delta = self.total_rx.saturating_sub(self.sample_rx);
            let tx_delta = self.total_tx.saturating_sub(self.sample_tx);
            self.sample_rx = self.total_rx;
            self.sample_tx = self.total_tx;
            self.rx_bps = (rx_delta as f64 / dt) as u64;
            self.tx_bps = (tx_delta as f64 / dt) as u64;
            self.last_rate_sample = now;
        }
    }

    fn connected_count(&self, idle_timeout: Duration) -> usize {
        let now = Instant::now();
        self.peers
            .values()
            .filter(|p| p.last_seen.map(|t| now.duration_since(t) <= idle_timeout).unwrap_or(false))
            .count()
    }
}

pub async fn run_server_tui(
    mut event_rx: mpsc::UnboundedReceiver<UiEvent>,
    cmd_tx: mpsc::UnboundedSender<UiCommand>,
    initial_key_count: usize,
    peer_idle_timeout: Duration,
) -> Result<()> {
    enable_raw_mode()?;
    let mut stdout = io::stdout();
    execute!(stdout, EnterAlternateScreen)?;
    let backend = CrosstermBackend::new(stdout);
    let mut terminal = Terminal::new(backend)?;

    let mut state = UiState::new(initial_key_count);
    state.log("Server TUI started".to_string());
    state.log("Keys: N=create key, Q/Esc=quit".to_string());

    let result = async {
        loop {
            while let Ok(event) = event_rx.try_recv() {
                state.apply(event);
            }
            state.tick();

            terminal.draw(|frame| {
                let root = Layout::default()
                    .direction(Direction::Vertical)
                    .constraints([
                        Constraint::Length(7),
                        Constraint::Length(8),
                        Constraint::Min(8),
                        Constraint::Length(3),
                    ])
                    .split(frame.area());

                let dashboard = vec![
                    Line::from(vec![Span::styled("Connected peers: ", Style::default().fg(Color::Cyan)), Span::raw(state.connected_count(peer_idle_timeout).to_string())]),
                    Line::from(vec![Span::styled("Access keys: ", Style::default().fg(Color::Green)), Span::raw(state.key_count.to_string())]),
                    Line::from(vec![Span::styled("RX rate: ", Style::default().fg(Color::Yellow)), Span::raw(format!("{} B/s", state.rx_bps))]),
                    Line::from(vec![Span::styled("TX rate: ", Style::default().fg(Color::Yellow)), Span::raw(format!("{} B/s", state.tx_bps))]),
                    Line::from(vec![Span::styled("Unauthorized probes: ", Style::default().fg(Color::Red)), Span::raw(state.unauthorized_packets.to_string())]),
                ];
                let dashboard_widget = Paragraph::new(dashboard)
                    .block(Block::default().title("OSTP Server Dashboard").borders(Borders::ALL));
                frame.render_widget(dashboard_widget, root[0]);

                let mut peer_lines: Vec<String> = state
                    .peers
                    .iter()
                    .map(|(peer, stat)| format!("{}  rx={}B tx={}B", peer, stat.rx_total, stat.tx_total))
                    .collect();
                peer_lines.sort();
                let peers_widget = Paragraph::new(peer_lines.join("\n"))
                    .block(Block::default().title("Peers").borders(Borders::ALL));
                frame.render_widget(peers_widget, root[1]);

                let logs = state.logs.iter().cloned().collect::<Vec<_>>().join("\n");
                let logs_widget = Paragraph::new(logs)
                    .block(Block::default().title("Logs").borders(Borders::ALL));
                frame.render_widget(logs_widget, root[2]);

                let controls = Paragraph::new("N=create client key | Q/Esc=shutdown")
                    .block(Block::default().title("Controls").borders(Borders::ALL));
                frame.render_widget(controls, root[3]);
            })?;

            if event::poll(Duration::from_millis(50))? {
                if let Event::Key(key) = event::read()? {
                    if key.kind == KeyEventKind::Press {
                        match key.code {
                            KeyCode::Char('n') => {
                                let _ = cmd_tx.send(UiCommand::CreateClientKey);
                            }
                            KeyCode::Char('q') | KeyCode::Esc => {
                                let _ = cmd_tx.send(UiCommand::Shutdown);
                                break;
                            }
                            _ => {}
                        }
                    }
                }
            }

            tokio::time::sleep(Duration::from_millis(16)).await;
        }

        Ok::<(), anyhow::Error>(())
    }
    .await;

    disable_raw_mode()?;
    execute!(terminal.backend_mut(), LeaveAlternateScreen)?;
    terminal.show_cursor()?;

    result
}
