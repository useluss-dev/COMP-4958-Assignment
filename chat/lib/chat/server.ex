defmodule Chat.Server do
  use GenServer

  @type state :: %{nicks: :ets.table()}
  @type set_result :: {:ok, :unchanged | :new | :updated} | {:error, :taken}

  @name {:global, Chat.Server}
  @table Chat.Table

  @spec start_link(term()) :: GenServer.on_start()
  def start_link(_) do
    GenServer.start_link(__MODULE__, nil, name: @name)
  end

  # API

  @spec set_nick(pid(), String.t()) :: set_result()
  def set_nick(pid, nick) do
    GenServer.call(@name, {:set, pid, nick})
  end

  @spec send_message(pid(), String.t(), String.t()) :: :ok | {:error, :no_nick | :no_such_user}
  def send_message(from_pid, to_nick, text) do
    GenServer.call(@name, {:msg, from_pid, to_nick, text})
  end

  @spec list_nicks() :: [String.t()]
  def list_nicks, do: GenServer.call(@name, :list_nicks)

  # Callbacks

  @impl true
  @spec init(term()) :: {:ok, state()}
  def init(_) do
    table = :ets.new(@table, [:named_table])
    {:ok, %{nicks: table}}
  end

  @impl true
  def handle_call({:set, pid, nick}, _from, state) do
    {:reply, put_nick(state.nicks, pid, nick), state}
  end

  def handle_call({:msg, from_pid, to_nick, text}, _from, state) do
    reply =
      with {:ok, from_nick} <- nick_of(state.nick, from_pid),
           {:ok, to_pid} <- pid_of(state.nick, to_nick) do
        Chat.Proxy.Worker.deliver(to_pid, "[#{from_nick}] #{text}")
      end

    {:reply, reply, state}
  end

  def handle_call(:list_nicks, _from, state) do
    nicks = state.nicks |> :ets.select([{{:"$1", :_}, [], [:"$1"]}]) |> Enum.sort()

    {:reply, nicks, state}
  end

  # Internal

  @spec put_nick(:ets.table(), pid(), String.t()) :: set_result()
  defp put_nick(table, pid, nick) do
    case :ets.lookup(table, nick) do
      [{^nick, ^pid}] -> {:ok, :unchanged}
      [{^nick, _other}] -> {:error, :taken}
      [] -> claim_nick(table, pid, nick)
    end
  end

  @spec claim_nick(:ets.table(), pid(), String.t()) :: {:ok, :new | :updated}
  defp claim_nick(table, pid, nick) do
    had_nick? = :ets.select_delete(table, [{{:_, pid}, [], [true]}]) > 0
    :ets.insert(table, {nick, pid})

    if had_nick?, do: {:ok, :updated}, else: {:ok, :new}
  end

  defp pid_of(table, nick) do
    case :ets.lookup(table, nick) do
      [{^nick, pid}] -> {:ok, pid}
      [] -> {:error, :no_such_user}
    end
  end

  defp nick_of(table, pid) do
    case :ets.select(table, [{{:"$1", pid}, [], [:"$1"]}]) do
      [nick] -> {:ok, nick}
      [] -> {:error, :no_nick}
    end
  end
end
