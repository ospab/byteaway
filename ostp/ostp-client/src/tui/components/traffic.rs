use ratatui::layout::Rect;
use ratatui::layout::{Constraint, Direction, Layout};
use ratatui::style::{Color, Style};
use ratatui::widgets::{Block, Borders, Sparkline};
use ratatui::Frame;

use crate::app::AppState;

pub struct TrafficComponent;

impl TrafficComponent {
    pub fn render(&self, frame: &mut Frame<'_>, area: Rect, state: &AppState) {
        let rows = Layout::default()
            .direction(Direction::Vertical)
            .constraints([Constraint::Percentage(50), Constraint::Percentage(50)])
            .split(area);

        let incoming = Sparkline::default()
            .block(Block::default().title("Incoming Distribution").borders(Borders::ALL))
            .data(&state.incoming_history)
            .style(Style::default().fg(Color::Green));

        let outgoing = Sparkline::default()
            .block(Block::default().title("Outgoing Distribution").borders(Borders::ALL))
            .data(&state.outgoing_history)
            .style(Style::default().fg(Color::Blue));

        frame.render_widget(incoming, rows[0]);
        frame.render_widget(outgoing, rows[1]);
    }
}
