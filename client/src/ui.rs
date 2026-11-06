use ratatui::{
    Frame,
    layout::{Alignment, Constraint, Layout, Rect},
    style::{Color, Modifier, Style},
    text::{Line, Span},
    widgets::{Block, BorderType, Paragraph},
};

use crate::app::{App, Entry, Kind};

pub fn render(app: &mut App, frame: &mut Frame) {
    let [log_area, input_area] =
        Layout::vertical([Constraint::Min(3), Constraint::Length(3)]).areas(frame.area());

    render_log(app, frame, log_area);
    render_input(app, frame, input_area);
}

fn style_for(kind: Kind) -> Style {
    match kind {
        Kind::Server => Style::default().fg(Color::Yellow),
        // body text of other users' messages; the [nick] label is colored separately
        Kind::Chat => Style::default(),
        Kind::Sent => Style::default().fg(Color::DarkGray),
        Kind::System => Style::default()
            .fg(Color::Cyan)
            .add_modifier(Modifier::ITALIC),
    }
}

/// Each nick gets a stable color. Yellow, cyan and gray are left out because
/// server lines, system notices and sent lines already use them.
fn nick_style(nick: &str) -> Style {
    const PALETTE: [Color; 6] = [
        Color::Green,
        Color::Magenta,
        Color::LightRed,
        Color::LightBlue,
        Color::LightGreen,
        Color::LightMagenta,
    ];
    let hash = nick
        .bytes()
        .fold(0u32, |h, b| h.wrapping_mul(31).wrapping_add(b as u32));
    Style::default()
        .fg(PALETTE[hash as usize % PALETTE.len()])
        .add_modifier(Modifier::BOLD)
}

/// Builds one visual row. `start` is the char offset of `chunk` within the
/// entry's text, so the `[nick]` label keeps its color even when a long
/// message wraps across rows.
fn styled_line(entry: &Entry, chunk: String, start: usize) -> Line<'static> {
    let base = style_for(entry.kind);

    let Some(nick) = &entry.nick else {
        return Line::styled(chunk, base);
    };

    let label_len = nick.chars().count() + 2; // "[" + nick + "]"
    let label_chars = label_len.saturating_sub(start).min(chunk.chars().count());
    if label_chars == 0 {
        return Line::styled(chunk, base);
    }

    let split = chunk
        .char_indices()
        .nth(label_chars)
        .map(|(i, _)| i)
        .unwrap_or(chunk.len());
    let (label, rest) = chunk.split_at(split);

    Line::from(vec![
        Span::styled(label.to_string(), nick_style(nick)),
        Span::styled(rest.to_string(), base),
    ])
}

/// Message log: wrap every entry to the width, then show the window that
/// ends `app.scroll` lines above the bottom.
fn render_log(app: &mut App, frame: &mut Frame, area: Rect) {
    let status = if app.connected {
        "connected"
    } else {
        "disconnected"
    };
    let block = Block::bordered()
        .title(format!(" chat · {status} "))
        .title_alignment(Alignment::Center)
        .border_type(BorderType::Rounded);

    let inner = block.inner(area);
    let (width, height) = (inner.width as usize, inner.height as usize);

    let mut lines: Vec<Line> = Vec::new();
    for entry in &app.messages {
        for (i, chunk) in wrap(&entry.text, width).into_iter().enumerate() {
            lines.push(styled_line(entry, chunk, i * width));
        }
    }

    // Clamp here, where we know the real size.
    let max_scroll = lines.len().saturating_sub(height);
    app.scroll = app.scroll.min(max_scroll);
    let end = lines.len() - app.scroll;
    let start = end.saturating_sub(height);

    frame.render_widget(
        Paragraph::new(lines[start..end].to_vec()).block(block),
        area,
    );
}

/// Input box: scrolls horizontally so the cursor is always visible.
fn render_input(app: &App, frame: &mut Frame, area: Rect) {
    let block = Block::bordered()
        .title(" message ")
        .border_type(BorderType::Rounded);

    let inner = block.inner(area);
    let visible_width = inner.width as usize;
    let offset = (app.cursor + 1).saturating_sub(visible_width);
    let shown: String = app.input.iter().skip(offset).take(visible_width).collect();

    frame.render_widget(Paragraph::new(shown).block(block), area);
    frame.set_cursor_position((inner.x + (app.cursor - offset) as u16, inner.y));
}

/// Hard-wraps text to `width` characters. Always returns at least one line.
fn wrap(text: &str, width: usize) -> Vec<String> {
    if width == 0 {
        return Vec::new();
    }
    let chars: Vec<char> = text.chars().collect();
    if chars.is_empty() {
        return vec![String::new()];
    }
    chars
        .chunks(width)
        .map(|chunk| chunk.iter().collect())
        .collect()
}
