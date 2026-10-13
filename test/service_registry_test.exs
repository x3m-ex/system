defmodule X3m.System.ServiceRegistryTest do
  use ExUnit.Case, async: false

  alias X3m.System.{ClusterCase, Dispatcher, Instrumenter, Message, ServiceRegistry}
  alias X3m.System.Test.{DistRouter, NonOkService, Router}

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

  describe "a crashed service registry" do
    test "is restarted and the application keeps running" do
      [peer] = ClusterCase.start_nodes(1)

      restarted = _crash_registry(peer)

      assert is_pid(restarted)
      assert {:ok, [:x3m_system]} == _started?(peer)
    end

    test "still offers the node's own services after its restart" do
      [peer] = ClusterCase.start_nodes(1)
      ClusterCase.register_router(peer, DistRouter)
      _await_on(peer, :remote_first, {:local, {DistRouter, :remote_first}})

      assert is_pid(_crash_registry(peer))

      _await_on(peer, :remote_first, {:local, {DistRouter, :remote_first}})
    end

    test "is offered again to peers after its restart" do
      [peer] = ClusterCase.start_nodes(1)
      ClusterCase.register_router(peer, DistRouter)
      ClusterCase.wait_until_discovered(:remote_first, [peer])

      assert is_pid(_crash_registry(peer))

      ClusterCase.wait_until_discovered(:remote_first, [peer])
      assert {:ok, :from_first} == Dispatcher.dispatch(Message.new(:remote_first)).response
    end

    test "is restarted after a kill and offers the node's own services again" do
      [peer] = ClusterCase.start_nodes(1)
      ClusterCase.register_router(peer, DistRouter)
      _await_on(peer, :remote_first, {:local, {DistRouter, :remote_first}})
      killed = :rpc.call(peer, Process, :whereis, [ServiceRegistry])

      true = :rpc.call(peer, Process, :exit, [killed, :kill])

      assert is_pid(_await_new_registry(peer, killed, 50))
      assert {:ok, [:x3m_system]} == _started?(peer)
      _await_on(peer, :remote_first, {:local, {DistRouter, :remote_first}})
    end

    test "learns the peers' services after its restart" do
      [provider, peer] = ClusterCase.start_nodes(2)
      ClusterCase.register_router(provider, DistRouter)
      _await_on(peer, :remote_first, {:remote, %{provider => DistRouter}})

      assert is_pid(_crash_registry(peer))

      _await_on(peer, :remote_first, {:remote, %{provider => DistRouter}})
    end
  end

  describe "a restarted x3m_system application" do
    test "offers the node's services to peers again" do
      [peer] = ClusterCase.start_nodes(1)
      ClusterCase.register_router(peer, DistRouter)
      ClusterCase.wait_until_discovered(:remote_first, [peer])

      :ok = :rpc.call(peer, Application, :stop, [:x3m_system])
      _await_on(node(), :remote_first, :not_found)
      {:ok, _apps} = :rpc.call(peer, Application, :ensure_all_started, [:x3m_system])

      ClusterCase.wait_until_discovered(:remote_first, [peer])
    end
  end

  describe "joining the cluster" do
    test "a node whose registry starts after it joined discovers a peer's services at once" do
      [provider] = ClusterCase.start_nodes(1)
      ClusterCase.register_router(provider, DistRouter)
      ClusterCase.wait_until_discovered(:remote_first, [provider])

      # connected to the cluster, but :x3m_system (and so its ServiceRegistry) not started yet
      [joiner] = ClusterCase.start_nodes(1, applications: [])
      :ok = _await_connected(provider, joiner)
      assert nil == :rpc.call(joiner, Process, :whereis, [ServiceRegistry])

      {:ok, _apps} = :rpc.call(joiner, Application, :ensure_all_started, [:x3m_system])

      _await_on(joiner, :remote_first, {:remote, %{provider => DistRouter}})
    end
  end

  # an unhandled call crashes the registry; returns its new pid, or nil if none came up
  defp _crash_registry(node) do
    crashed = :rpc.call(node, Process, :whereis, [ServiceRegistry])
    {:badrpc, _reason} = :rpc.call(node, GenServer, :call, [ServiceRegistry, :unknown_request])
    _await_new_registry(node, crashed, 50)
  end

  defp _await_new_registry(node, crashed, 0) do
    case :rpc.call(node, Process, :whereis, [ServiceRegistry]) do
      ^crashed -> nil
      pid -> pid
    end
  end

  defp _await_new_registry(node, crashed, attempts_left) do
    case :rpc.call(node, Process, :whereis, [ServiceRegistry]) do
      pid when is_pid(pid) and pid != crashed ->
        pid

      _not_yet ->
        Process.sleep(40)
        _await_new_registry(node, crashed, attempts_left - 1)
    end
  end

  defp _started?(node) do
    node
    |> :rpc.call(Application, :started_applications, [])
    |> List.keymember?(:x3m_system, 0)
    |> case do
      true -> {:ok, [:x3m_system]}
      false -> {:error, :x3m_system_not_running}
    end
  end

  defp _await_connected(node_a, node_b, attempts_left \\ 50)
  defp _await_connected(_node_a, _node_b, 0), do: :not_connected

  defp _await_connected(node_a, node_b, attempts_left) do
    if node_b in :rpc.call(node_a, Node, :list, []) do
      :ok
    else
      Process.sleep(40)
      _await_connected(node_a, node_b, attempts_left - 1)
    end
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
