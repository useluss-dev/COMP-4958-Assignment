defmodule Chat.Proxy.Worker do
  use GenServer

  @spec start(:gen_tcp.socket()) :: GenServer.on_start()
  def start(socket), do: GenServer.start(__MODULE__, socket)

  @impl true
  @spec init(:gen_tcp.socket()) :: {:ok, :gen_tcp.socket()}
  def init(socket) do
    {:ok, socket}
  end
end
