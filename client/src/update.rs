use ratatui::crossterm::event::{KeyCode, KeyEvent, KeyModifiers, MouseEvent, MouseEventKind};

use crate::app::App;

pub fn update(app: &mut App, key_event: KeyEvent) {
    let ctrl = key_event.modifiers.contains(KeyModifiers::CONTROL);

    match key_event.code {
        KeyCode::Esc => app.quit(),
        KeyCode::Char('c' | 'C') if ctrl => app.quit(),

        KeyCode::Enter => app.submit(),

        KeyCode::Left if ctrl => app.home(),
        KeyCode::Right if ctrl => app.end(),

        // `q`, `j`, `k` etc. are now just text
        KeyCode::Char(c) if !ctrl => app.insert_char(c),

        KeyCode::Backspace => app.backspace(),
        KeyCode::Delete => app.delete(),
        KeyCode::Left => app.move_left(),
        KeyCode::Right => app.move_right(),

        KeyCode::PageUp => app.scroll_up(5),
        KeyCode::PageDown => app.scroll_down(5),
        _ => {}
    };
}

/// Mouse capture is enabled by `Tui::enter`, so wheel events arrive here.
pub fn update_mouse(app: &mut App, mouse_event: MouseEvent) {
    match mouse_event.kind {
        MouseEventKind::ScrollUp => app.scroll_up(3),
        MouseEventKind::ScrollDown => app.scroll_down(3),
        _ => {}
    }
}
