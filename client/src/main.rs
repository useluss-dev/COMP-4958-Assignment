use std::{
    io::{self, BufRead, BufReader, Write},
    net::{Shutdown, TcpStream},
    process, thread,
};

fn main() {
    let mut stream = match TcpStream::connect("127.0.0.1:6666") {
        Ok(s) => s,
        Err(e) => {
            eprintln!("Failed to connect: {e}");
            process::exit(1);
        }
    };

    let read_half = match stream.try_clone() {
        Ok(s) => s,
        Err(e) => {
            eprintln!("Could not clone stream: {e}");
            process::exit(1);
        }
    };

    let reader_thread = thread::spawn(move || {
        let reader = BufReader::new(read_half);
        for line in reader.lines() {
            match line {
                Ok(l) => println!("{l}"),
                Err(e) => {
                    eprintln!("read error: {e}");
                    break;
                }
            }
        }
        println!("server closed the connection");
    });

    let stdin = io::stdin();
    prompt();
    for line in stdin.lock().lines() {
        let line = match line {
            Ok(l) => l,
            Err(e) => {
                eprintln!("stdin error: {e}");
                break;
            }
        };

        if let Err(e) = stream.write_all(format!("{line}\n").as_bytes()) {
            eprintln!("write error: {e}");
            break;
        }

        prompt();
    }

    if let Err(e) = stream.shutdown(Shutdown::Write) {
        eprintln!("shutdown error: {e}");
    }

    if reader_thread.join().is_err() {
        eprintln!("reader thread panicked");
    }
}

fn prompt() {
    print!("> ");
    if let Err(e) = io::stdout().flush() {
        eprintln!("flush error: {e}");
    }
}
