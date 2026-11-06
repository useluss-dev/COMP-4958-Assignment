defmodule Chat.Proxy.Worker do
  use GenServer
  require Logger

  defmodule State do
    @enforce_keys [:socket]
    defstruct [:socket, nick: nil]

    @type t :: %__MODULE__{socket: :gen_tcp.socket(), nick: String.t() | nil}
  end

  @spec start(:gen_tcp.socket()) :: GenServer.on_start()
  def start(socket), do: GenServer.start(__MODULE__, socket)

  # API

  @spec activate(pid()) :: :ok
  def activate(pid), do: GenServer.cast(pid, :activate)

  @spec deliver(pid(), String.t()) :: :ok
  def deliver(pid, text), do: GenServer.cast(pid, {:deliver, text})

  # Callbacks

  @impl true
  @spec init(:gen_tcp.socket()) :: {:ok, State.t()}
  def init(socket), do: {:ok, %State{socket: socket}}

  @impl true
  def handle_cast(:activate, state) do
    case :inet.setopts(state.socket, active: :once) do
      :ok -> {:noreply, state}
      {:error, reason} -> {:stop, {:shutdown, reason}, state}
    end
  end

  def handle_cast({:deliver, text}, state) do
    send_line(state.socket, text)
    {:noreply, state}
  end

  @impl true
  def handle_info({:tcp, socket, data}, %State{socket: socket} = state) do
    :inet.setopts(socket, active: :once)
    {:noreply, parse_input(state, data)}
  end

  def handle_info({:tcp_closed, socket}, %State{socket: socket} = state),
    do: {:stop, :normal, socket}

  # Internal

  # Every command takes the state and returns the (possibly updated) state.
  defp parse_input(state, input) do
    input = String.trim(input, "\n")
    Logger.info("#{inspect(input)}")

    case String.split(input) do
      [command | args] -> handle_command(state, String.upcase(command), args)
      [] -> Logger.info("nothing")
    end
  end

  # Handle /L Command
  defp handle_command(state, "/L", _args) do
    case Chat.Server.list_nicks() do
      [] -> send_line(state.socket, "no users online")
      nicks -> send_line(state.socket, "online:\n" <> Enum.join(nicks, "\n"))
    end

    state
  end

  # Handle /N Command
  defp handle_command(%State{} = state, "/N", [nick | _args]) do
    case Chat.Server.set_nick(self(), nick) do
      {:ok, :new} ->
        send_line(state.socket, "nickname successfully set to #{nick}")
        %State{state | nick: nick}

      {:ok, :updated} ->
        send_line(state.socket, "nickname successfully updated to #{nick}")
        %State{state | nick: nick}

      {:ok, :unchanged} ->
        send_line(state.socket, "you already have the nickname #{nick}")
        state

      {:error, :taken} ->
        send_line(state.socket, "#{nick} is already taken please try another name")
        state
    end
  end

  defp handle_command(state, "/N", []) do
    send_line(state.socket, "usage: /N <nickname>")
    state
  end

  # Handle calling commands without nickname
  defp handle_command(%State{nick: nil} = state, cmd, _args)
       when cmd in ["/M", "/B", "/D", "/G"] do
    send_line(state.socket, "set a nickname first with /N <nickname")
  end

  # Handle invalid command
  defp handle_command(state, cmd, _args) do
    send_line(state.socket, "#{cmd} is an invalid command")
    state
  end

  # Send text to client
  defp send_line(socket, text) do
    case :gen_tcp.send(socket, text <> "\n") do
      :ok -> :ok
      {:error, reason} -> Logger.warning("send failed: #{inspect(reason)}")
    end
  end
end
