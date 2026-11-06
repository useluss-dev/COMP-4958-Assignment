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

  # Delivers to every listed nick that has a pid and is active. Everything else is skipped
  @spec send_message(pid(), String.t() | [String.t()], String.t()) :: :ok | {:error, :no_nick}
  def send_message(from_pid, to_nicks, text) do
    GenServer.call(@name, {:msg, from_pid, List.wrap(to_nicks), text})
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
    result = put_nick(state.nicks, pid, nick)
    if result == {:ok, :new}, do: Process.monitor(pid)
    {:reply, result, state}
  end

  def handle_call({:msg, from_pid, to_nicks, text}, _from, state) do
    reply =
      with {:ok, from_nick} <- nick_of(state.nicks, from_pid) do
        deliver_all(state.nicks, to_nicks, "[#{from_nick}] #{text}")
      end

    {:reply, reply, state}
  end

  def handle_call(:list_nicks, _from, state) do
    nicks = state.nicks |> :ets.select([{{:"$1", :_}, [], [:"$1"]}]) |> Enum.sort()

    {:reply, nicks, state}
  end

  @impl true
  def handle_info({:DOWN, _ref, :process, pid, _reason}, state) do
    :ets.select_delete(state.nicks, [{{:_, pid}, [], [true]}])
    {:noreply, state}
  end

  # Internal

  @spec deliver_all(:ets.table(), [String.t()], String.t()) :: :ok
  defp deliver_all(table, nicks, message) do
    for nick <- Enum.uniq(nicks), {:ok, pid} <- [pid_of(table, nick)] do
      Chat.Proxy.Worker.deliver(pid, message)
    end

    :ok
  end

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

  @spec pid_of(:ets.table(), String.t()) :: {:ok, pid()} | {:error, :no_such_user}
  defp pid_of(table, nick) do
    case :ets.lookup(table, nick) do
      [{^nick, pid}] -> {:ok, pid}
      [] -> {:error, :no_such_user}
    end
  end

  @spec nick_of(:ets.table(), pid()) :: {:ok, String.t()} | {:error, :no_nick}
  defp nick_of(table, pid) do
    case :ets.select(table, [{{:"$1", pid}, [], [:"$1"]}]) do
      [nick] -> {:ok, nick}
      [] -> {:error, :no_nick}
    end
  end
end
