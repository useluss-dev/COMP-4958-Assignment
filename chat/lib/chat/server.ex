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

  # Client API

  @spec set_nick(pid(), String.t()) :: set_result()
  def set_nick(pid, nick) do
    GenServer.call(@name, {:set, pid, nick})
  end

  # Server API

  @impl true
  @spec init(term()) :: {:ok, state()}
  def init(_) do
    table = :ets.new(@table, [:named_table])
    {:ok, %{nicks: table}}
  end

  @impl true
  @spec handle_call({:set, pid(), String.t()}, GenServer.from(), state()) ::
          {:reply, set_result(), state()}
  def handle_call({:set, pid, nick}, _from, state) do
    {:reply, put_nick(state.nicks, pid, nick), state}
  end

  # Helpers

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
end
