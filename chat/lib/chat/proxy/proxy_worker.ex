defmodule Chat.Proxy.Worker do
  use GenServer
  require Logger

  @spec start(:gen_tcp.socket()) :: GenServer.on_start()
  def start(socket), do: GenServer.start(__MODULE__, socket)

  @spec activate(pid()) :: :ok
  def activate(pid), do: GenServer.cast(pid, :activate)

  @impl true
  @spec init(:gen_tcp.socket()) :: {:ok, :gen_tcp.socket()}
  def init(socket) do
    {:ok, socket}
  end

  @impl true
  def handle_cast(:activate, socket) do
    case :inet.setopts(socket, active: :once) do
      :ok -> {:noreply, socket}
      {:error, reason} -> {:stop, {:shutdown, reason}, socket}
    end
  end

  @impl true
  def handle_info({:tcp, socket, data}, socket) do
    :inet.setopts(socket, active: :once)
    Logger.info("[#{inspect(self())}] received: #{inspect(data)}")
    {:noreply, socket}
  end

  def handle_info({:tcp_closed, socket}, socket), do: {:stop, :normal, socket}
end
