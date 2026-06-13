defmodule Banking.Core.Application do
  @moduledoc false
  use Application

  def start(_type, _args) do
    Banking.TelemetryLogger.setup()
    :ok = Banking.Core.Router.register_services()

    children = _get_children()

    opts = [strategy: :one_for_one, name: Banking.Core.MainSupervisor]
    Supervisor.start_link(children, opts)
  end

  case Mix.env() do
    :test ->
      defp _get_children, do: []

    _ ->
      defp _get_children do
        event_store_config =
          Application.get_env(:banking_core, Banking.Core.EventStore)

        [
          {Banking.Core.EventStore, event_store_config},
          {X3m.System.LocalAggregatesSupervision, [Banking.Core.LocalAggregates, Banking.Core]}
        ]
      end
  end
end
