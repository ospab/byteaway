use ratatui::layout::Rect;
use ratatui::widgets::{Block, Borders, Paragraph};
use ratatui::Frame;

use crate::app::AppState;

pub struct LogsComponent;

impl LogsComponent {
    pub fn render(&self, frame: &mut Frame<'_>, area: Rect, state: &AppState) {
        let lines: Vec<String> = state.logs.iter().cloned().collect();
        let widget = Paragraph::new(lines.join("\n"))
            .block(Block::default().title("Logs").borders(Borders::ALL))
            .scroll((state.log_scroll, 0));
        frame.render_widget(widget, area);
    }
}
