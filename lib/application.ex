defmodule X3m.System.Application do
  @moduledoc !"""
             Internal. OTP application that starts the task supervisor, node monitor and
             service registry, and wires up node telemetry handlers.
             """

  use Application

  def start(_type, _args) do
    X3m.System.ServiceTelemetryHandler.setup()

    children = [
      {Task.Supervisor, name: X3m.System.TaskSupervisor},
      X3m.System.NodeMonitor,
      X3m.System.ServiceRegistry
    ]

    opts = [strategy: :one_for_one, name: __MODULE__]
    Supervisor.start_link(children, opts)
  end
end
