defmodule X3m.System.DistributedDispatchTest do
  use ExUnit.Case, async: false

  alias X3m.System.ClusterCase
  alias X3m.System.Dispatcher
  alias X3m.System.Message
  alias X3m.System.Test.DistRouter

  # These services are hosted only on the peer nodes, never on this (manager) node, so the
  # exact same `Dispatcher.dispatch(msg)` call transparently routes across the cluster.

  test "dispatches to a remote node and the reply crosses back" do
    [server] = ClusterCase.start_nodes(1)

    ClusterCase.register_router(server, DistRouter)
    ClusterCase.wait_until_discovered(:remote_first, [server])

    msg = Message.new(:remote_first)

    assert %Message{response: {:ok, :from_first}} = Dispatcher.dispatch(msg)
  end

  test "when every remote node asks for another node, no node is available" do
    [server_1, server_2] = ClusterCase.start_nodes(2)

    ClusterCase.register_router(server_1, DistRouter)
    ClusterCase.register_router(server_2, DistRouter)
    ClusterCase.put_node_env(server_1, :reject_quorum?, true)
    ClusterCase.put_node_env(server_2, :reject_quorum?, true)
    ClusterCase.wait_until_discovered(:maybe_another_node, [server_1, server_2])

    msg = Message.new(:maybe_another_node)

    assert %Message{response: {:error, {:no_nodes_available, tried_nodes}}} =
             Dispatcher.dispatch(msg)

    assert Enum.sort([
             {server_1, :quorum_not_met},
             {server_2, :quorum_not_met}
           ]) == Enum.sort(tried_nodes)
  end

  test "when one remote node asks for another node, the responding node is used" do
    [server_1, server_2] = ClusterCase.start_nodes(2)

    ClusterCase.register_router(server_1, DistRouter)
    ClusterCase.register_router(server_2, DistRouter)
    ClusterCase.put_node_env(server_1, :reject_quorum?, true)
    ClusterCase.put_node_env(server_2, :reject_quorum?, false)
    ClusterCase.wait_until_discovered(:maybe_another_node, [server_1, server_2])

    msg = Message.new(:maybe_another_node)

    assert %Message{response: {:ok, :from_quorum}} = Dispatcher.dispatch(msg)
  end
end
