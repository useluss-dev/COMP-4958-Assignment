defmodule Chat.Proxy.Worker do
  use GenServer
  require Logger

  @nick_regex ~r/\A[a-z][a-zA-Z0-9_]*\z/

  defmodule State do
    @enforce_keys [:socket]
    defstruct [:socket, nick: nil, groups: %{"default" => []}]

    @type t :: %__MODULE__{
            socket: :gen_tcp.socket(),
            nick: String.t() | nil,
            groups: %{String.t() => String.t()}
          }
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
      [] -> tell(state, "no users online")
      nicks -> tell(state, "online:\n" <> Enum.join(nicks, "\n"))
    end
  end

  # Handle /N Command
  defp handle_command(%State{} = state, "/N", [nick | _args]) do
    if valid_nick?(nick) do
      case Chat.Server.set_nick(self(), nick) do
        {:ok, :new} ->
          tell(%State{state | nick: nick}, "nickname successfully set to #{nick}")

        {:ok, :updated} ->
          tell(%State{state | nick: nick}, "nickname successfully updated to #{nick}")

        {:ok, :unchanged} ->
          tell(state, "you already have the nickname #{nick}")

        {:error, :taken} ->
          tell(state, "#{nick} is already taken please try another name")
      end
    else
      tell(
        state,
        "valid nicknames must start with a lowercase and only contain alphanumeric and underscore characters"
      )
    end
  end

  defp handle_command(state, "/N", []) do
    tell(state, "usage: /N <nickname>")
  end

  # Handle calling commands without nickname
  defp handle_command(%State{nick: nil} = state, cmd, _args)
       when cmd in ["/M", "/B", "/D", "/G"] do
    tell(state, "set a nickname first with /N <nickname")
  end

  # Handle invalid command
  defp handle_command(state, cmd, _args) do
    tell(state, "#{cmd} is an invalid command")
  end

  # Send text to client
  @spec send_line(:gen_tcp.socket(), String.t()) :: :ok | {:error, String.t()}
  defp send_line(socket, text) do
    case :gen_tcp.send(socket, text <> "\n") do
      :ok -> :ok
      {:error, reason} -> Logger.warning("send failed: #{inspect(reason)}")
    end
  end

  # Send a line to this client and hand the state back, so handlers can end with it.
  @spec tell(State.t(), String.t()) :: State.t()
  defp tell(%State{} = state, text) do
    send_line(state.socket, text)
    state
  end

  @spec valid_nick?(String.t()) :: boolean()
  defp valid_nick?(nick), do: nick =~ @nick_regex
end
