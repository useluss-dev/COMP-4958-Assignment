use std::{
    io::{BufRead, BufReader},
    net::TcpStream,
    sync::mpsc,
    thread,
    time::{Duration, Instant},
};

use color_eyre::Result;
use ratatui::crossterm::event::{
    self, Event as CrosstermEvent, KeyEvent, KeyEventKind, MouseEvent,
};

/// Terminal and network events.
///
/// No longer `Copy` because `Server` carries a `String`.
#[derive(Clone, Debug)]
pub enum Event {
    /// Terminal tick.
    Tick,
    /// Key press.
    Key(KeyEvent),
    /// Mouse click/scroll.
    Mouse(MouseEvent),
    /// Terminal resize.
    Resize(u16, u16),
    /// One line received from the chat server.
    Server(String),
    /// The server closed the connection (or the read failed).
    Disconnected,
}

/// Event handler: merges terminal input and server lines into one channel.
#[derive(Debug)]
pub struct EventHandler {
    /// Event receiver channel.
    receiver: mpsc::Receiver<Event>,
}

impl EventHandler {
    /// Constructs a new instance of [`EventHandler`] and starts its threads.
    pub fn new(tick_rate: u64, read_half: TcpStream) -> Self {
        let (sender, receiver) = mpsc::channel();
        spawn_terminal_thread(sender.clone(), Duration::from_millis(tick_rate));
        spawn_network_thread(sender, read_half);
        Self { receiver }
    }

    /// Receive the next event from the handler threads.
    ///
    /// Blocks until something happens. Since every server line and keypress
    /// arrives here, the UI redraws immediately instead of waiting for a tick.
    pub fn next(&self) -> Result<Event> {
        Ok(self.receiver.recv()?)
    }
}

/// Forwards crossterm events and periodic ticks.
fn spawn_terminal_thread(sender: mpsc::Sender<Event>, tick_rate: Duration) {
    thread::spawn(move || {
        let mut last_tick = Instant::now();
        loop {
            let timeout = tick_rate.saturating_sub(last_tick.elapsed());

            if event::poll(timeout).expect("unable to poll for event") {
                let forwarded = match event::read().expect("unable to read event") {
                    // ignore KeyEventKind::Release on windows
                    CrosstermEvent::Key(e) if e.kind == KeyEventKind::Press => Some(Event::Key(e)),
                    CrosstermEvent::Mouse(e) => Some(Event::Mouse(e)),
                    CrosstermEvent::Resize(w, h) => Some(Event::Resize(w, h)),
                    // focus / paste / key release: nothing to do
                    _ => None,
                };

                if let Some(ev) = forwarded
                    && sender.send(ev).is_err()
                {
                    return; // UI is gone
                }
            }

            if last_tick.elapsed() >= tick_rate {
                if sender.send(Event::Tick).is_err() {
                    return;
                }
                last_tick = Instant::now();
            }
        }
    });
}

/// Reads lines from the server and forwards them.
fn spawn_network_thread(sender: mpsc::Sender<Event>, read_half: TcpStream) {
    thread::spawn(move || {
        for line in BufReader::new(read_half).lines() {
            match line {
                Ok(l) => {
                    if sender.send(Event::Server(l)).is_err() {
                        return; // UI is gone
                    }
                }
                Err(_) => break,
            }
        }
        let _ = sender.send(Event::Disconnected);
    });
}
