defmodule X3m.System.Application do
  @moduledoc false

  use Application

  def start(_type, _args) do
    X3m.System.ServiceTelemetryHandler.setup()

    children = [
      X3m.System.NodeMonitor,
      X3m.System.ServiceRegistry
    ]

    opts = [strategy: :one_for_one, name: __MODULE__]
    Supervisor.start_link(children, opts)
  end
end
