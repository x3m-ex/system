defmodule X3m.System.DistributedDispatchTest do
  use ExUnit.Case, async: false

  alias X3m.System.ClusterCase
  alias X3m.System.Dispatcher
  alias X3m.System.Message
  alias X3m.System.Test.DistRouter
  alias X3m.System.Test.NonOkService

  # These services are hosted only on the peer nodes, never on this (manager) node, so the
  # exact same `Dispatcher.dispatch(msg)` call transparently routes across the cluster.

  test "dispatches to a remote node and the reply crosses back" do
    [server] = ClusterCase.start_nodes(1)

    ClusterCase.register_router(server, DistRouter)
    ClusterCase.wait_until_discovered(:remote_first, [server])

    msg = Message.new(:remote_first)

    assert %Message{response: {:ok, :from_first}} = Dispatcher.dispatch(msg)
  end

  test "an infinite timeout is accepted for a remote service" do
    [server] = ClusterCase.start_nodes(1)

    ClusterCase.register_router(server, DistRouter)
    ClusterCase.wait_until_discovered(:remote_first, [server])

    msg = Message.new(:remote_first)

    assert %Message{response: {:ok, :from_first}} = Dispatcher.dispatch(msg, timeout: :infinity)
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

  describe "slow remote handler" do
    setup do
      {cluster, [server]} = ClusterCase.start_cluster(1)

      ClusterCase.register_router(server, DistRouter)
      ClusterCase.wait_until_discovered(:slow_remote, [server])

      {:ok, cluster: cluster, server: server}
    end

    test "times out at the dispatch timeout, not when the handler returns" do
      msg = Message.new(:slow_remote, raw_request: %{sleep_ms: 3_000})
      started_at = System.monotonic_time(:millisecond)

      assert %Message{response: {:service_timeout, :slow_remote, _id, 200}} =
               Dispatcher.dispatch(msg, timeout: 200)

      assert System.monotonic_time(:millisecond) - started_at < 1_000
    end

    test "the dispatch timeout wins over the remote call's own timeout" do
      msg = Message.new(:slow_remote, raw_request: %{sleep_ms: 1_000})

      responses =
        1..200
        |> Enum.map(fn _attempt -> Dispatcher.dispatch(msg, timeout: 0).response end)
        |> Enum.uniq()

      assert [{:service_timeout, :slow_remote, msg.id, 0}] == responses
    end

    test "a late reply after the timeout does not reach the caller" do
      msg = Message.new(:slow_remote, raw_request: %{sleep_ms: 400})

      assert %Message{response: {:service_timeout, :slow_remote, _id, 100}} =
               Dispatcher.dispatch(msg, timeout: 100)

      refute_receive _late_message, 1_000
    end

    test "a relay whose caller dies early stops once the remote call times out" do
      msg = Message.new(:slow_remote, raw_request: %{sleep_ms: 4_000})
      caller = spawn(fn -> Dispatcher.dispatch(msg, timeout: 500) end)

      Process.sleep(100)
      assert [_relay] = Task.Supervisor.children(X3m.System.TaskSupervisor)
      Process.exit(caller, :kill)

      Process.sleep(2_500)
      assert [] == Task.Supervisor.children(X3m.System.TaskSupervisor)
    end

    test "a relay killed mid-dispatch returns an error, not a service timeout" do
      msg = Message.new(:slow_remote, raw_request: %{sleep_ms: 3_000, test_pid: self()})
      dispatch = Task.async(fn -> Dispatcher.dispatch(msg, timeout: 2_000) end)

      assert_receive {:handler, _handler}, 1_000
      assert [relay] = Task.Supervisor.children(X3m.System.TaskSupervisor)
      Process.exit(relay, :kill)

      assert %Message{response: {:error, {:badrpc, {:EXIT, :killed}}}} = Task.await(dispatch)
    end

    test "the remote handler keeps running after the dispatch timeout", %{server: server} do
      msg = Message.new(:slow_remote, raw_request: %{sleep_ms: 3_000, test_pid: self()})

      assert %Message{response: {:service_timeout, :slow_remote, _id, 100}} =
               Dispatcher.dispatch(msg, timeout: 100)

      assert_receive {:handler, handler}, 2_000
      assert node(handler) == server
      assert :rpc.call(server, Process, :alive?, [handler])
    end

    test "the remote handler keeps running after its caller dies", %{server: server} do
      test_pid = self()
      msg = Message.new(:slow_remote, raw_request: %{sleep_ms: 3_000, test_pid: test_pid})
      caller = spawn(fn -> Dispatcher.dispatch(msg, timeout: 5_000) end)

      assert_receive {:handler, handler}, 2_000
      Process.exit(caller, :kill)
      Process.sleep(200)

      assert :rpc.call(server, Process, :alive?, [handler])
    end

    test "the node going down mid-call returns an error", %{cluster: cluster, server: server} do
      msg = Message.new(:slow_remote, raw_request: %{sleep_ms: 5_000})

      spawn(fn ->
        Process.sleep(200)
        LocalCluster.stop(cluster, server)
      end)

      assert %Message{response: {:error, {:badrpc, :nodedown}}} =
               Dispatcher.dispatch(msg, timeout: 10_000)
    end
  end

  describe "failing remote handler" do
    setup do
      [server] = ClusterCase.start_nodes(1)

      ClusterCase.register_router(server, DistRouter)
      ClusterCase.wait_until_discovered(:throwing_remote, [server])

      :ok
    end

    test "a raise returns an error" do
      msg = Message.new(:raising_remote)

      assert %Message{
               response:
                 {:error, {:badrpc, {:EXIT, {%RuntimeError{message: "handler failed"}, _stack}}}}
             } = Dispatcher.dispatch(msg, timeout: 1_000)
    end

    test "an exit returns an error" do
      msg = Message.new(:exiting_remote)

      assert %Message{response: {:error, {:badrpc, {:EXIT, :handler_exited}}}} =
               Dispatcher.dispatch(msg, timeout: 1_000)
    end

    test "a throw returns an error" do
      msg = Message.new(:throwing_remote)

      assert %Message{response: {:error, {:badrpc, {:throw, :handler_threw}}}} =
               Dispatcher.dispatch(msg, timeout: 1_000)
    end
  end

  describe "service returning other than :ok" do
    setup do
      [server] = ClusterCase.start_nodes(1)

      ClusterCase.register_router(server, NonOkService)
      ClusterCase.wait_until_discovered(:not_ok, [server])

      {:ok, server: server}
    end

    test "a remote one returns a bad return error, not a service timeout" do
      msg = Message.new(:not_ok)

      assert %Message{response: {:error, {:badrpc, {:bad_return, :not_ok}}}} =
               Dispatcher.dispatch(msg, timeout: 1_000)
    end

    test "a remote one returning a handler tuple returns a bad return error" do
      msg = Message.new(:handler_tuple)

      assert %Message{response: {:error, {:badrpc, {:bad_return, {:handler, :not_a_monitor}}}}} =
               Dispatcher.dispatch(msg, timeout: 1_000)
    end

    test "a remote one returning a badrpc tuple returns a bad return error" do
      msg = Message.new(:badrpc_tuple)

      assert %Message{response: {:error, {:badrpc, {:bad_return, {:badrpc, :not_a_failure}}}}} =
               Dispatcher.dispatch(msg, timeout: 1_000)
    end

    test "a local one returns the same bad return error as a remote one", %{server: server} do
      msg = Message.new(:not_ok)

      assert %Message{response: {:error, {:badrpc, {:bad_return, :not_ok}}}} =
               :rpc.call(server, Dispatcher, :dispatch, [msg, [timeout: 1_000]])
    end
  end

  describe "remote authorization" do
    test "is answered by the providing node" do
      [server] = ClusterCase.start_nodes(1)

      ClusterCase.register_router(server, DistRouter)
      ClusterCase.wait_until_discovered(:remote_first, [server])

      assert true == Dispatcher.authorized?(Message.new(:remote_first))
    end

    test "a check slower than the timeout returns an error at the timeout" do
      [server] = ClusterCase.start_nodes(1)

      ClusterCase.register_router(server, DistRouter)
      ClusterCase.wait_until_discovered(:remote_first, [server])

      msg = Message.new(:remote_first, raw_request: %{authorize_sleep_ms: 3_000})
      started_at = System.monotonic_time(:millisecond)

      assert {:error, {:badrpc, :timeout}} == Dispatcher.authorized?(msg, timeout: 200)
      assert System.monotonic_time(:millisecond) - started_at < 1_000
    end

    test "the node going down mid-check returns an error" do
      {cluster, [server]} = ClusterCase.start_cluster(1)

      ClusterCase.register_router(server, DistRouter)
      ClusterCase.wait_until_discovered(:remote_first, [server])

      msg = Message.new(:remote_first, raw_request: %{authorize_sleep_ms: 5_000})

      spawn(fn ->
        Process.sleep(200)
        LocalCluster.stop(cluster, server)
      end)

      assert {:error, {:badrpc, :nodedown}} == Dispatcher.authorized?(msg, timeout: 10_000)
    end

    test "a failing node is skipped for the next provider" do
      [server_1, server_2] = ClusterCase.start_nodes(2)

      ClusterCase.register_router(server_1, DistRouter)
      ClusterCase.register_router(server_2, DistRouter)
      ClusterCase.wait_until_discovered(:remote_first, [server_1, server_2])

      msg = Message.new(:remote_first)
      [{first_asked, _router} | _other_providers] = Dispatcher.discover_service(msg)
      ClusterCase.put_node_env(first_asked, :fail_authorize?, true)

      assert true == Dispatcher.authorized?(msg)
    end
  end
end
