defmodule Chat.Proxy do
  use GenServer
  require Logger

  @spec start_link(:inet.port_number()) :: GenServer.on_start()
  def start_link(port), do: GenServer.start_link(__MODULE__, port)

  @impl true
  @spec init(:inet.port_number()) :: {:ok, :gen_tcp.socket()}
  def init(port) do
    opts = [:binary, active: false, packet: :line, reuseaddr: true]

    {:ok, listen} = :gen_tcp.listen(port, opts)
    send(self(), :accept)

    {:ok, listen}
  end

  @impl true
  @spec handle_info(:accpet, :gen_tcp.socket()) :: {:noreply, :gen_tcp.socket()}
  def handle_info(:accept, listen) do
    {:ok, socket} = :gen_tcp.accept(listen)
    Logger.info("[#{inspect(self())}]: accepted connection #{inspect(socket)}")

    {:ok, pid} = Chat.Proxy.Worker.start(socket)
    :gen_tcp.controlling_process(socket, pid)

    send(self(), :accept)
    {:noreply, listen}
  end
end
