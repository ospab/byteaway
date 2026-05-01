use ratatui::layout::Rect;
use ratatui::style::{Color, Style};
use ratatui::text::{Line, Span};
use ratatui::widgets::{Block, Borders, Paragraph};
use ratatui::Frame;

use crate::app::AppState;

pub struct DashboardComponent;

impl DashboardComponent {
    pub fn render(&self, frame: &mut Frame<'_>, area: Rect, state: &AppState) {
        let lines = vec![
            Line::from(vec![Span::styled("Connection: ", Style::default().fg(Color::Cyan)), Span::raw(state.status.as_str())]),
            Line::from(vec![Span::styled("RTT: ", Style::default().fg(Color::Yellow)), Span::raw(format!("{:.1} ms", state.rtt_ms))]),
            Line::from(vec![Span::styled("Throughput: ", Style::default().fg(Color::Green)), Span::raw(format!("{} bps", state.throughput_bps))]),
            Line::from(vec![Span::styled("Profile: ", Style::default().fg(Color::Magenta)), Span::raw(format!("{:?}", state.active_profile))]),
        ];

        let widget = Paragraph::new(lines).block(Block::default().title("OSTP Dashboard").borders(Borders::ALL));
        frame.render_widget(widget, area);
    }
}
