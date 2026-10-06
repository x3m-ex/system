defmodule X3m.System.ServiceRegistryTest do
  use ExUnit.Case, async: false

  alias X3m.System.{ClusterCase, Instrumenter, ServiceRegistry}
  alias X3m.System.Test.{NonOkService, Router}

  test "a node introduces the public services of every router it registered" do
    [peer] = ClusterCase.start_nodes(1)
    services = %{public: %{second_router_service: NonOkService}, private: %{}}
    Instrumenter.execute(:register_local_services, %{}, services)
    send({ServiceRegistry, peer}, {:unregister_node_services, node()})
    _await_on(peer, :first, :not_found)

    send(ServiceRegistry, {:introduce_local_services, peer})

    _await_on(peer, :second_router_service, {:remote, %{node() => NonOkService}})
    _await_on(peer, :first, {:remote, %{node() => Router}})
  end

  defp _await_on(node, service, expected, attempts_left \\ 50)

  defp _await_on(node, service, expected, 0) do
    seen = :rpc.call(node, ServiceRegistry, :find_nodes_with_service, [service])
    failure = "#{inspect(node)} saw #{inspect(seen)} for #{inspect(service)}"
    flunk("#{failure}, not #{inspect(expected)}")
  end

  defp _await_on(node, service, expected, attempts_left) do
    node
    |> :rpc.call(ServiceRegistry, :find_nodes_with_service, [service])
    |> case do
      ^expected ->
        :ok

      _not_yet ->
        Process.sleep(40)
        _await_on(node, service, expected, attempts_left - 1)
    end
  end
end
