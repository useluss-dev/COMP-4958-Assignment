defmodule Chat.Proxy.Worker do
  use GenServer
  require Logger

  @nick_regex ~r/\A[a-z][a-zA-Z0-9_]*\z/
  @group_regex ~r/\A[A-Z][a-zA-Z0-9_]*\z/

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

  def handle_info({:tcp_closed, socket}, %State{socket: socket} = _state),
    do: {:stop, :normal, socket}

  # Internal

  # Every command takes the state and returns the (possibly updated) state.
  defp parse_input(state, input) do
    input = String.trim(input, "\n")
    Logger.info("#{inspect(input)}")

    case String.split(input) do
      [command | args] -> handle_command(state, normalize(command), args)
      [] -> Logger.info("nothing")
    end
  end

  # /L
  defp handle_command(state, "/L", _args) do
    case Chat.Server.list_nicks() do
      [] -> tell(state, "no users online")
      nicks -> tell(state, "online:\n" <> Enum.join(nicks, "\n"))
    end
  end

  # /N <nickname>
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

  defp handle_command(state, "/N", []), do: tell(state, "usage: /N <nickname>")

  # Handle calling commands without nickname
  defp handle_command(%State{nick: nil} = state, cmd, _args)
       when cmd in ["/M", "/B", "/D", "/G"] do
    tell(state, "set a nickname first with /N <nickname")
  end

  # /M <name[,name...]> <message>
  defp handle_command(%State{} = state, "/M", [to | words]) when words != [] do
    send_to(state, expand(state.groups, split_names(to)), Enum.join(words, " "))
  end

  defp handle_command(%State{} = state, "/M", _args),
    do: tell(state, "usage: /M <name[,name...]> <message>")

  # /G <Group> <name[,name...]>   (replaces the group's members)
  defp handle_command(%State{} = state, "/G", [group, members | _]) do
    if valid_group?(group) do
      case resolve(state.groups, split_names(members)) do
        {:ok, nicks} ->
          state = %State{state | groups: Map.put(state.groups, group, nicks)}
          tell(state, "group #{group}: " <> Enum.join(nicks, ","))

        {:error, invalid} ->
          tell(state, "invalid name: #{invalid}")
      end
    else
      tell(
        state,
        "group names must start with an uppercase letter and only contain alphanumeric and underscore characters"
      )
    end
  end

  defp handle_command(%State{} = state, "/G", _args),
    do: tell(state, "usage: /G <Group> <name[,name...]>")

  # /D <name[,name...]>
  defp handle_command(%State{} = state, "/D", [members | _]) do
    case resolve(state.groups, split_names(members)) do
      {:ok, nicks} ->
        state = %State{state | groups: Map.put(state.groups, "default", nicks)}
        tell(state, "default group: " <> Enum.join(nicks, ","))

      {:error, invalid} ->
        tell(state, "invalid name: #{invalid}")
    end
  end

  defp handle_command(%State{} = state, "/D", []),
    do: tell(state, "usage: /D <name[,name...]>")

  # /B <message>
  defp handle_command(%State{} = state, "/B", words) when words != [] do
    send_to(state, Map.get(state.groups, "default", []), Enum.join(words, " "))
  end

  defp handle_command(%State{} = state, "/B", []), do: tell(state, "usage: /B <message>")

  # Handle invalid command
  defp handle_command(state, cmd, _args), do: tell(state, "#{cmd} is an invalid command")

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

  # Nicknames start with lowercase and can only contain alphanumeric + underscore characters.
  @spec valid_nick?(String.t()) :: boolean()
  defp valid_nick?(nick), do: nick =~ @nick_regex

  # Groups start with uppercase and can only contain alphanumeric + underscore characters.
  @spec valid_group?(String.t()) :: boolean()
  defp valid_group?(name), do: name =~ @group_regex

  @spec split_names(String.t()) :: [String.t()]
  defp split_names(list), do: String.split(list, ",", trim: true)

  @spec expand(State.groups(), [String.t()]) :: [String.t()]
  defp expand(groups, names) do
    names
    |> Enum.flat_map(fn name ->
      if valid_group?(name), do: Map.get(groups, name, []), else: [name]
    end)
    |> Enum.uniq()
  end

  @spec resolve(State.groups(), [String.t()]) :: {:ok, [String.t()]} | {:error, String.t()}
  defp resolve(groups, names) do
    case Enum.find(names, &(not valid_nick?(&1) and not valid_group?(&1))) do
      nil -> {:ok, expand(groups, names)}
      invalid -> {:error, invalid}
    end
  end

  # Note: nicknames without a pid are silently skipped
  @spec send_to(State.t(), [String.t()], String.t()) :: State.t()
  defp send_to(%State{} = state, nicks, text) do
    Chat.Server.send_message(self(), nicks, text)
    tell(state, "message sent")
  end

  # Only the first two characters count, so /M, /m, /message and /Msg all become "/M".
  @spec normalize(String.t()) :: String.t()
  defp normalize(command), do: command |> String.slice(0, 2) |> String.upcase()
end
