defmodule Chat.Proxy.Worker do
  use GenServer
  require Logger

  @spec start(:gen_tcp.socket()) :: GenServer.on_start()
  def start(socket), do: GenServer.start(__MODULE__, socket)

  # API

  @spec activate(pid()) :: :ok
  def activate(pid), do: GenServer.cast(pid, :activate)

  @spec deliver(pid(), String.t()) :: :ok
  def deliver(pid, text), do: GenServer.cast(pid, {:deliver, text})

  # Callbacks

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

  def handle_cast({:deliver, text}, socket) do
    send_line(socket, text)
    {:noreply, socket}
  end

  @impl true
  def handle_info({:tcp, socket, data}, socket) do
    :inet.setopts(socket, active: :once)
    parse_input(socket, data)
    {:noreply, socket}
  end

  # Internal

  def handle_info({:tcp_closed, socket}, socket), do: {:stop, :normal, socket}

  defp parse_input(socket, input) do
    input = String.trim(input, "\n")
    Logger.info("#{inspect(input)}")

    case String.split(input) do
      [command | args] -> handle_command(socket, String.upcase(command), args)
      [] -> Logger.info("nothing")
    end
  end

  defp handle_command(socket, "/L", _args) do
    case Chat.Server.list_nicks() do
      [] -> send_line(socket, "no users online")
      nicks -> send_line(socket, "online:\n" <> Enum.join(nicks, "\n"))
    end
  end

  # Handle invalid command
  defp handle_command(socket, cmd, _args) do
    send_line(socket, "#{cmd} is an invalid command")
  end

  # Send text to client
  defp send_line(socket, text) do
    case :gen_tcp.send(socket, text <> "\n") do
      :ok -> :ok
      {:error, reason} -> Logger.warning("send failed: #{inspect(reason)}")
    end
  end
end
