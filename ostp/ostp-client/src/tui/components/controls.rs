use ratatui::layout::Rect;
use ratatui::style::{Color, Style};
use ratatui::text::{Line, Span};
use ratatui::widgets::{Block, Borders, Paragraph};
use ratatui::Frame;

pub struct ControlsComponent;

impl ControlsComponent {
    pub fn render(&self, frame: &mut Frame<'_>, area: Rect) {
        let text = vec![
            Line::from(vec![Span::styled("Space", Style::default().fg(Color::Cyan)), Span::raw(" - Start/Stop tunnel")]),
            Line::from(vec![Span::styled("Tab", Style::default().fg(Color::Cyan)), Span::raw(" - Next obfuscation profile")]),
            Line::from(vec![Span::styled("K", Style::default().fg(Color::Cyan)), Span::raw(" - Edit server/key config")]),
            Line::from(vec![Span::styled("B", Style::default().fg(Color::Cyan)), Span::raw(" - Detach TUI (background)")]),
            Line::from(vec![Span::styled("Up/Down", Style::default().fg(Color::Cyan)), Span::raw(" - Scroll logs")]),
            Line::from(vec![Span::styled("Esc/Q", Style::default().fg(Color::Cyan)), Span::raw(" - Exit")]),
        ];

        let widget = Paragraph::new(text).block(Block::default().title("Controls").borders(Borders::ALL));
        frame.render_widget(widget, area);
    }
}
