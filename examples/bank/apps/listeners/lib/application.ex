defmodule Banking.Listeners.Application do
  @moduledoc false
  use Application

  def start(_type, _args) do
    Banking.TelemetryLogger.setup()
    Banking.Migrations.create(:banking_listeners)
    Banking.Migrations.up(:banking_listeners)

    :ok = Banking.Listeners.Router.register_services()

    children = _get_children()

    opts = [strategy: :one_for_one, name: Banking.Listeners.MainSupervisor]
    Supervisor.start_link(children, opts)
  end

  case Mix.env() do
    :test ->
      defp _get_children do
        [Banking.Listeners.Repo]
      end

    _ ->
      defp _get_children do
        event_store_config =
          Application.get_env(:banking_listeners, Banking.Listeners.EventStore)

        [
          Banking.Listeners.Repo,
          {Banking.Listeners.EventStore, event_store_config},
          {Banking.Listeners.Accounts.Listener, [Banking.Listeners.EventStore]}
        ]
      end
  end
end
