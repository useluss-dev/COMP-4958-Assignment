use std::{
    io::Write,
    net::{Shutdown, TcpStream},
};

/// Where a log entry came from (used for styling).
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum Kind {
    /// Any other line from the server (acks, errors, ...).
    Server,
    /// A message from another user, parsed from `[nick] text`.
    Chat,
    /// A line you sent.
    Sent,
    /// A notice from the client itself.
    System,
}

/// One line in the message log.
#[derive(Debug)]
pub struct Entry {
    pub kind: Kind,
    pub text: String,
    /// Sender's nickname, set for `Kind::Chat` (text still holds the full `[nick] ...` line).
    pub nick: Option<String>,
}

/// Application.
#[derive(Debug)]
pub struct App {
    /// should the application exit?
    pub should_quit: bool,
    /// is the server connection still usable?
    pub connected: bool,
    /// message log
    pub messages: Vec<Entry>,
    /// input line being edited
    pub input: Vec<char>,
    /// cursor position within `input` (in chars)
    pub cursor: usize,
    /// lines scrolled up from the bottom (0 = following new messages)
    pub scroll: usize,
    /// write half of the connection
    stream: TcpStream,
}

impl App {
    /// Constructs a new instance of [`App`].
    pub fn new(stream: TcpStream) -> Self {
        let peer = stream
            .peer_addr()
            .map(|a| a.to_string())
            .unwrap_or_else(|_| "server".into());

        Self {
            should_quit: false,
            connected: true,
            messages: vec![Entry {
                kind: Kind::System,
                text: format!("connected to {peer} (Esc or Ctrl-C to quit)"),
                nick: None,
            }],
            input: Vec::new(),
            cursor: 0,
            scroll: 0,
            stream,
        }
    }

    /// Set should_quit to true to quit the application.
    pub fn quit(&mut self) {
        self.should_quit = true;
    }

    /// Closes the socket, which also unblocks the reader thread.
    pub fn close(&mut self) {
        let _ = self.stream.shutdown(Shutdown::Both);
    }

    fn push(&mut self, kind: Kind, text: String) {
        self.messages.push(Entry {
            kind,
            text,
            nick: None,
        });
    }

    /// A line arrived from the server. `[nick] text` is a message from another
    /// user; anything else is a plain server line.
    pub fn receive(&mut self, line: String) {
        match Self::chat_nick(&line) {
            Some(nick) => self.messages.push(Entry {
                kind: Kind::Chat,
                nick: Some(nick),
                text: line,
            }),
            None => self.push(Kind::Server, line),
        }
    }

    /// Extracts the nick from a `[nick] text` line.
    fn chat_nick(line: &str) -> Option<String> {
        let rest = line.strip_prefix('[')?;
        let (nick, _text) = rest.split_once("] ")?;
        if nick.is_empty() || nick.contains(char::is_whitespace) || nick.contains(']') {
            return None;
        }
        Some(nick.to_string())
    }

    /// The server went away.
    pub fn disconnected(&mut self) {
        if self.connected {
            self.connected = false;
            self.push(Kind::System, "server closed the connection".into());
        }
    }

    /// Sends the current input line to the server.
    pub fn submit(&mut self) {
        let line: String = self.input.drain(..).collect();
        self.cursor = 0;

        let line = line.trim();
        if line.is_empty() {
            return;
        }

        if !self.connected {
            self.push(Kind::System, "not connected".into());
            return;
        }

        match writeln!(self.stream, "{line}") {
            Ok(()) => {
                self.scroll = 0;
                self.push(Kind::Sent, format!("> {line}"));
            }
            Err(e) => {
                self.connected = false;
                self.push(Kind::System, format!("write error: {e}"));
            }
        }
    }

    pub fn insert_char(&mut self, c: char) {
        self.input.insert(self.cursor, c);
        self.cursor += 1;
    }

    pub fn backspace(&mut self) {
        if self.cursor > 0 {
            self.cursor -= 1;
            self.input.remove(self.cursor);
        }
    }

    pub fn delete(&mut self) {
        if self.cursor < self.input.len() {
            self.input.remove(self.cursor);
        }
    }

    pub fn move_left(&mut self) {
        self.cursor = self.cursor.saturating_sub(1);
    }

    pub fn move_right(&mut self) {
        self.cursor = (self.cursor + 1).min(self.input.len());
    }

    pub fn home(&mut self) {
        self.cursor = 0;
    }

    pub fn end(&mut self) {
        self.cursor = self.input.len();
    }

    pub fn scroll_up(&mut self, lines: usize) {
        // clamped to the real maximum when rendering
        self.scroll = self.scroll.saturating_add(lines);
    }

    pub fn scroll_down(&mut self, lines: usize) {
        self.scroll = self.scroll.saturating_sub(lines);
    }
}
