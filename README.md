# Elixir TCP Chat

This project provides an Elixir chat server, and a Rust TUI client.

## How It Works

The chat server works by running a core server + a proxy on two different nodes. The server is globally registered and the proxy node is able to communicate with it via `Node.connect()`. The proxy opens a TCP port and listens for clients connecting to the port. When a client connects it passes that TCP connection to a proxy worker that will handle validating client commands and sending them to the server.

## Commands

- `/L` -> Lists all of the currently online users.
- `/N <nickname>` -> Sets your nickname. Setting your nickname is required to designate you as online commands other than `/L` and `/N` cannot be used without first setting a nickname.
- `/M <name[,name...]> <message>` -> Send a message to a user or list of users.
- `/G <group-name> <name[,name...]>` -> Creates or updates a group of users. Group names can be used anywhere names can be used.
- `/D <name[,name...]>` -> Updates the users in the default group.
- `/B <message>` -> Broadcasts a message to user in the default group.

## How To Run

In order to run this project you will need at least 3 terminals.

Terminal 1 the server:
```
cd chat/
iex --sname server -S mix
```

Terminal 2 the proxy:
```
cd chat/
CHAT_ROLE="proxy" iex --sname proxy -S mix
```

Once you're in `iex` you will need to run the `Node.connect()` function to connect the server which should be at `:"server@<hostname>"`.

Terminal 3+ the clients:
```
cd client/
cargo run
```
