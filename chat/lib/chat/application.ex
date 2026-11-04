defmodule Chat.Application do
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    opts = [strategy: :one_for_one, name: Chat.Supervisor]
    Supervisor.start_link(children(System.get_env("CHAT_ROLE", "server")), opts)
  end

  defp children("server"), do: [Chat.Server]
  defp children("proxy"), do: [{Chat.Proxy, 6666}]
end
