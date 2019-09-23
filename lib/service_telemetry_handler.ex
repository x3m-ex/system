defmodule X3m.System.ServiceTelemetryHandler do
  require Logger

  def setup do
    events = [
      [:x3m, :system, :node_joined],
      [:x3m, :system, :node_left]
    ]

    config = %{service_registry: X3m.System.ServiceRegistry}

    :telemetry.attach_many("x3m-system-node_handler", events, &handle_event/4, config)
  end

  @doc false
  def handle_event(
        [:x3m, :system, :node_joined],
        _measurements,
        %{node: node},
        %{service_registry: service_registry}
      ) do
    Logger.debug(fn -> "[Discovery] Asking node #{inspect(node)} for local services" end)
    request = {:introduce_local_services, Node.self()}

    send({service_registry, node}, request)
  end

  @doc false
  def handle_event(
        [:x3m, :system, :node_left],
        _measurements,
        %{node: node},
        %{service_registry: service_registry}
      ) do
    request = {:unregister_node_services, node}
    send(service_registry, request)
  end
end
