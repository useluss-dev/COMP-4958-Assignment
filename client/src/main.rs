/// Application.
pub mod app;

/// Terminal events handler.
pub mod event;

/// Widget renderer.
pub mod ui;

/// Terminal user interface.
pub mod tui;

/// Application updater.
pub mod update;

use std::net::TcpStream;

use app::App;
use color_eyre::{Result, eyre::WrapErr};
use event::{Event, EventHandler};
use ratatui::{Terminal, backend::CrosstermBackend};
use tui::Tui;
use update::{update, update_mouse};

const ADDR: &str = "127.0.0.1:6666";
const TICK_RATE_MS: u64 = 250;

fn main() -> Result<()> {
    color_eyre::install()?;

    // Connect before entering the alternate screen so errors print normally.
    let stream =
        TcpStream::connect(ADDR).wrap_err_with(|| format!("failed to connect to {ADDR}"))?;

    // The event handler gets its own handle on the socket for the reader thread.
    let events = EventHandler::new(TICK_RATE_MS, stream.try_clone()?);
    let mut app = App::new(stream);

    // Initialize the terminal user interface.
    let backend = CrosstermBackend::new(std::io::stderr());
    let terminal = Terminal::new(backend)?;
    let mut tui = Tui::new(terminal, events);
    tui.enter()?;

    // Start the main loop.
    while !app.should_quit {
        // Render the user interface.
        tui.draw(&mut app)?;
        // Handle events.
        match tui.events.next()? {
            Event::Tick | Event::Resize(_, _) => {}
            Event::Key(key_event) => update(&mut app, key_event),
            Event::Mouse(mouse_event) => update_mouse(&mut app, mouse_event),
            Event::Server(line) => app.receive(line),
            Event::Disconnected => app.disconnected(),
        };
    }

    // Exit the user interface.
    tui.exit()?;
    app.close();
    Ok(())
}
