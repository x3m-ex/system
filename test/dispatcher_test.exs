defmodule X3m.System.DispatcherTest do
  use ExUnit.Case, async: false
  alias X3m.System.{Message, Dispatcher, Instrumenter, ServiceRegistry}
  alias X3m.System.Test.NonOkService

  test "invoke unavailable service" do
    msg = _new_message(:wrong_service)
    assert %Message{response: {:service_unavailable, :wrong_service}} = Dispatcher.dispatch(msg)
  end

  test "default unauthorized service call" do
    msg = _new_message(:unauthorized_service)
    assert %Message{response: {:error, :forbidden}} = Dispatcher.dispatch(msg)
  end

  test "custom unauthorized service call" do
    msg = _new_message(:custom_unauthorized_service)

    assert %Message{response: {:error, {:forbidden, "None shall pass!"}}} =
             Dispatcher.dispatch(msg)
  end

  test "node can't process request" do
    msg = _new_message(:try_another_node)

    assert %Message{response: {:error, {:no_nodes_available, [local: :quorum_not_met]}}} =
             Dispatcher.dispatch(msg)
  end

  test "invoke local service" do
    msg = _new_message(:first)
    assert %Message{response: {:ok, :from_first}} = Dispatcher.dispatch(msg)
  end

  test "invoke private service" do
    msg = _new_message(:private_service)
    assert %Message{response: {:ok, :from_private}} = Dispatcher.dispatch(msg)
  end

  test "a late local reply after the timeout does not reach the caller" do
    msg = Message.new(:slow, raw_request: %{sleep_ms: 300, test_pid: self()})

    assert %Message{response: {:service_timeout, :slow, _id, 100}} =
             Dispatcher.dispatch(msg, timeout: 100)

    assert_receive {:handler, handler}
    _await_exit(handler)

    refute_receive _late_message, 100
  end

  test "a local handler keeps running after the dispatch timeout" do
    msg = Message.new(:slow, raw_request: %{sleep_ms: 500, test_pid: self()})

    assert %Message{response: {:service_timeout, :slow, _id, 100}} =
             Dispatcher.dispatch(msg, timeout: 100)

    assert_receive {:handler, handler}
    assert Process.alive?(handler)
    _await_exit(handler)
  end

  describe "failing local handler" do
    test "a raise returns an error without waiting for the timeout" do
      started_at = System.monotonic_time(:millisecond)

      assert %Message{
               response:
                 {:error, {:badrpc, {:EXIT, {%RuntimeError{message: "handler failed"}, _stack}}}}
             } = Dispatcher.dispatch(Message.new(:raising), timeout: 5_000)

      assert System.monotonic_time(:millisecond) - started_at < 1_000
    end

    test "an exit returns an error" do
      assert %Message{response: {:error, {:badrpc, {:EXIT, :handler_exited}}}} =
               Dispatcher.dispatch(Message.new(:exiting), timeout: 5_000)
    end

    test "a throw returns an error" do
      assert %Message{response: {:error, {:badrpc, {:throw, :handler_threw}}}} =
               Dispatcher.dispatch(Message.new(:throwing), timeout: 5_000)
    end
  end

  describe "handler replying from another process after it returned" do
    test "always answers" do
      msg = Message.new(:delegated, raw_request: %{reply_after_ms: 5})

      responses =
        1..500
        |> Enum.map(fn _attempt -> Dispatcher.dispatch(msg, timeout: 1_000).response end)
        |> Enum.uniq()

      assert [{:ok, :from_delegate}] == responses
    end

    test "always times out when the reply comes too late" do
      msg = Message.new(:delegated, raw_request: %{reply_after_ms: 50})

      responses =
        1..200
        |> Enum.map(fn _attempt -> Dispatcher.dispatch(msg, timeout: 10).response end)
        |> Enum.uniq()

      assert [{:service_timeout, :delegated, msg.id, 10}] == responses
    end
  end

  test "if service call is authorized" do
    assert Dispatcher.authorized?(_new_message(:first)) == true
    assert Dispatcher.authorized?(_new_message(:private_service)) == true
    assert Dispatcher.authorized?(_new_message(:try_another_node)) == true
    assert Dispatcher.authorized?(_new_message(:unauthorized_service)) == false
    assert Dispatcher.authorized?(_new_message(:custom_unauthorized_service)) == false
    assert Dispatcher.authorized?(_new_message(:wrong_service)) == :service_unavailable
  end

  describe "validate/1" do
    test "it sets dry_run to true before invoking dispatch if dry_run was false (default)" do
      assert %Message{dry_run: true, response: {:ok, :from_first}} =
               Dispatcher.validate(_new_message(:first))
    end

    test "it doesn't change dry_run if it wasn't false" do
      assert %Message{dry_run: :verbose} =
               Dispatcher.validate(_new_message(:first) |> Map.put(:dry_run, :verbose))
    end
  end

  describe "telemetry" do
    test "events when invoking existing service" do
      {test_name, _arity} = __ENV__.function
      parent = self()
      ref = make_ref()
      service_name = :first

      _attach_handlers_to_telemetry(test_name, service_name, parent, ref)

      msg = _new_message(service_name)
      assert %Message{response: {:ok, :from_first}} = Dispatcher.dispatch(msg)

      assert_receive {^ref, :discovering_service}
      refute_receive {^ref, :service_not_found}
      assert_receive {^ref, :service_found}
      refute_receive {^ref, :checking_if_service_call_is_authorized}
      assert_receive {^ref, :invoking_service}
      assert_receive {^ref, :service_request_received}
      assert_receive {^ref, :executing_service}
      assert_receive {^ref, :execution_finished}
      assert_receive {^ref, :service_responded}

      :telemetry.detach(to_string(test_name))
    end

    test "events when invoking non-existing service" do
      {test_name, _arity} = __ENV__.function
      parent = self()
      ref = make_ref()
      service_name = :wrong_service

      _attach_handlers_to_telemetry(test_name, service_name, parent, ref)

      msg = _new_message(service_name)
      assert %Message{response: {:service_unavailable, :wrong_service}} = Dispatcher.dispatch(msg)

      assert_receive {^ref, :discovering_service}
      assert_receive {^ref, :service_not_found}
      refute_receive {^ref, :service_found}
      refute_receive {^ref, :checking_if_service_call_is_authorized}
      refute_receive {^ref, :invoking_service}
      refute_receive {^ref, :service_request_received}
      refute_receive {^ref, :executing_service}
      refute_receive {^ref, :execution_finished}
      refute_receive {^ref, :service_responded}

      :telemetry.detach(to_string(test_name))
    end

    test "events when validating existing service" do
      {test_name, _arity} = __ENV__.function
      parent = self()
      ref = make_ref()
      service_name = :first

      _attach_handlers_to_telemetry(test_name, service_name, parent, ref)

      msg = _new_message(service_name)
      assert %Message{response: {:ok, :from_first}} = Dispatcher.validate(msg)

      assert_receive {^ref, :discovering_service}
      refute_receive {^ref, :service_not_found}
      assert_receive {^ref, :service_found}
      refute_receive {^ref, :checking_if_service_call_is_authorized}
      assert_receive {^ref, :invoking_service}
      assert_receive {^ref, :service_request_received}
      assert_receive {^ref, :executing_service}
      assert_receive {^ref, :execution_finished}
      assert_receive {^ref, :service_validation_responded}

      :telemetry.detach(to_string(test_name))
    end

    test "events when validating non-existing service" do
      {test_name, _arity} = __ENV__.function
      parent = self()
      ref = make_ref()
      service_name = :wrong_service

      _attach_handlers_to_telemetry(test_name, service_name, parent, ref)

      msg = _new_message(service_name)
      assert %Message{response: {:service_unavailable, :wrong_service}} = Dispatcher.validate(msg)

      assert_receive {^ref, :discovering_service}
      assert_receive {^ref, :service_not_found}
      refute_receive {^ref, :service_found}
      refute_receive {^ref, :checking_if_service_call_is_authorized}
      refute_receive {^ref, :invoking_service}
      refute_receive {^ref, :service_request_received}
      refute_receive {^ref, :executing_service}
      refute_receive {^ref, :execution_finished}
      refute_receive {^ref, :service_validation_responded}

      :telemetry.detach(to_string(test_name))
    end

    test "events when authorizing existing service" do
      {test_name, _arity} = __ENV__.function
      parent = self()
      ref = make_ref()
      service_name = :first

      _attach_handlers_to_telemetry(test_name, service_name, parent, ref)

      msg = _new_message(service_name)
      assert true == Dispatcher.authorized?(msg)

      refute_receive {^ref, :discovering_service}
      refute_receive {^ref, :service_not_found}
      refute_receive {^ref, :service_found}
      assert_receive {^ref, :checking_if_service_call_is_authorized}
      refute_receive {^ref, :invoking_service}
      refute_receive {^ref, :service_request_received}
      refute_receive {^ref, :executing_service}
      refute_receive {^ref, :execution_finished}
      refute_receive {^ref, :service_responded}

      :telemetry.detach(to_string(test_name))
    end

    test "events when authorizing non-existing service" do
      {test_name, _arity} = __ENV__.function
      parent = self()
      ref = make_ref()
      service_name = :wrong_service

      _attach_handlers_to_telemetry(test_name, service_name, parent, ref)

      msg = _new_message(service_name)
      assert :service_unavailable == Dispatcher.authorized?(msg)

      refute_receive {^ref, :discovering_service}
      refute_receive {^ref, :service_not_found}
      refute_receive {^ref, :service_found}
      assert_receive {^ref, :checking_if_service_call_is_authorized}
      refute_receive {^ref, :invoking_service}
      refute_receive {^ref, :service_request_received}
      refute_receive {^ref, :executing_service}
      refute_receive {^ref, :execution_finished}
      refute_receive {^ref, :service_responded}

      :telemetry.detach(to_string(test_name))
    end
  end

  defp _attach_handlers_to_telemetry(test_name, service_name, parent, ref) do
    :telemetry.attach_many(
      to_string(test_name),
      [
        [:x3m, :system, :discovering_service],
        [:x3m, :system, :service_not_found],
        [:x3m, :system, :service_found],
        [:x3m, :system, :checking_if_service_call_is_authorized],
        [:x3m, :system, :invoking_service],
        [:x3m, :system, :service_responded],
        [:x3m, :system, :service_request_received],
        [:x3m, :system, :executing_service],
        [:x3m, :system, :execution_finished]
      ],
      __MODULE__.telemetry_handler(service_name, parent, ref),
      nil
    )
  end

  def telemetry_handler(service_name, parent, ref) do
    caller_node = Node.self()

    fn
      [:x3m, :system, :discovering_service], _measurements, meta, _config ->
        assert %{caller_node: ^caller_node, message: %Message{service_name: ^service_name}} =
                 meta

        send(parent, {ref, :discovering_service})

      [:x3m, :system, :service_not_found], _measurements, meta, _config ->
        assert %{caller_node: ^caller_node, message: %Message{service_name: ^service_name}} =
                 meta

        send(parent, {ref, :service_not_found})

      [:x3m, :system, :service_found], _measurements, meta, _config ->
        assert %{caller_node: ^caller_node, message: %Message{service_name: ^service_name}} =
                 meta

        send(parent, {ref, :service_found})

      [:x3m, :system, :checking_if_service_call_is_authorized], _measurements, meta, _config ->
        assert %{caller_node: ^caller_node, message: %Message{service_name: ^service_name}} =
                 meta

        send(parent, {ref, :checking_if_service_call_is_authorized})

      [:x3m, :system, :service_request_received], _measurements, meta, _config ->
        assert %{service: ^service_name} = meta
        send(parent, {ref, :service_request_received})

      [:x3m, :system, :invoking_service], _measurements, meta, _config ->
        assert %{message: %Message{service_name: ^service_name}, caller_node: _} = meta
        send(parent, {ref, :invoking_service})

      [:x3m, :system, :executing_service], _measurements, meta, _config ->
        assert %{service: ^service_name} = meta
        send(parent, {ref, :executing_service})

      [:x3m, :system, :execution_finished], _measurements, meta, _config ->
        assert %{message: %Message{service_name: ^service_name}} = meta
        send(parent, {ref, :execution_finished})

      [:x3m, :system, :service_responded],
      measurements,
      %{message: %Message{dry_run: false}} = meta,
      _config ->
        assert %{message: %Message{service_name: ^service_name}} = meta
        assert is_integer(measurements.duration)
        send(parent, {ref, :service_responded})

      [:x3m, :system, :service_responded], measurements, meta, _config ->
        assert %{message: %Message{service_name: ^service_name}} = meta
        assert is_integer(measurements.duration)
        send(parent, {ref, :service_validation_responded})

      event, measurements, meta, _config ->
        IO.inspect([event, measurements, meta], label: "Unexpected telemetry calls")
    end
  end

  describe "authorize/1 by assigns" do
    test "authorizes and dispatches when assigns carry the admin marker" do
      msg =
        :admin_only
        |> Message.new()
        |> Message.assign(:invoked_by, %{admin?: true})

      assert Dispatcher.authorized?(msg) == true
      assert %Message{response: {:ok, :from_first}} = Dispatcher.dispatch(msg)
    end

    test "denies by default when the admin marker is absent" do
      msg = Message.new(:admin_only)

      assert Dispatcher.authorized?(msg) == false
      assert %Message{response: {:error, :forbidden}} = Dispatcher.dispatch(msg)
    end
  end

  describe "discovery" do
    test "a missing service is logged as a warning" do
      log =
        ExUnit.CaptureLog.capture_log(fn ->
          assert %Message{response: {:service_unavailable, :wrong_service}} =
                   Dispatcher.dispatch(_new_message(:wrong_service))
        end)

      assert log =~ "[Discovery] Service wrong_service NOT found!"
    end

    test "does not wait for a busy service registry" do
      :ok = :sys.suspend(ServiceRegistry)
      on_exit(fn -> :sys.resume(ServiceRegistry) end)

      assert true == Dispatcher.authorized?(_new_message(:first))

      assert %Message{response: {:ok, :from_first}} =
               Dispatcher.dispatch(_new_message(:first), timeout: 1_000)
    end

    test "a service registered by the caller is discovered by its next dispatch" do
      misses =
        1..200
        |> Enum.count(fn attempt ->
          service = :"registered_by_caller_#{attempt}"
          services = %{public: %{service => NonOkService}, private: %{}}
          Instrumenter.execute(:register_local_services, %{}, services)

          :not_found ==
            service
            |> Message.new()
            |> Dispatcher.discover_service()
        end)

      assert 0 == misses
    end

    test "a service whose last remote provider leaves is no longer discovered" do
      registration = {:register_remote_services, {:ghost@nohost, [{:ghost_service, Ghost}]}}
      send(ServiceRegistry, registration)

      _state = :sys.get_state(ServiceRegistry)

      on_exit(fn ->
        send(ServiceRegistry, {:unregister_node_services, :ghost@nohost})
        _state = :sys.get_state(ServiceRegistry)
      end)

      assert [{:ghost@nohost, Ghost}] == Dispatcher.discover_service(Message.new(:ghost_service))

      send(ServiceRegistry, {:unregister_node_services, :ghost@nohost})
      _state = :sys.get_state(ServiceRegistry)

      assert :not_found == Dispatcher.discover_service(Message.new(:ghost_service))
    end

    test "a local provider wins over a remote one" do
      send(ServiceRegistry, {:register_remote_services, {:ghost@nohost, [{:first, Ghost}]}})

      on_exit(fn ->
        send(ServiceRegistry, {:unregister_node_services, :ghost@nohost})
        _state = :sys.get_state(ServiceRegistry)
      end)

      _state = :sys.get_state(ServiceRegistry)

      assert [{:local, X3m.System.Test.Router}] ==
               Dispatcher.discover_service(Message.new(:first))
    end
  end

  describe "with the service registry stopped" do
    setup do
      _stop_service_registry()
      on_exit(&_restart_service_registry/0)
    end

    test "dispatch returns service unavailable instead of exiting the caller" do
      assert %Message{response: {:service_unavailable, :first}} =
               Dispatcher.dispatch(_new_message(:first))
    end

    test "authorized? returns service unavailable instead of exiting the caller" do
      assert :service_unavailable == Dispatcher.authorized?(_new_message(:first))
    end

    test "a lookup logs that the registry is not running" do
      log =
        ExUnit.CaptureLog.capture_log(fn ->
          assert :not_found == ServiceRegistry.find_nodes_with_service(:first)
        end)

      assert log =~ "[Discovery] Service registry is not running, service first NOT found!"
    end
  end

  # the supervisor is held so it cannot restart the registry while the test runs
  defp _stop_service_registry do
    registry = Process.whereis(ServiceRegistry)
    ref = Process.monitor(registry)
    :ok = :sys.suspend(X3m.System.Application)
    Process.exit(registry, :kill)
    assert_receive {:DOWN, ^ref, :process, ^registry, :killed}
  end

  # a killed registry leaves its telemetry handler attached, which would fail its restart
  defp _restart_service_registry do
    :ok = :telemetry.detach("x3m-system-services")
    :ok = :sys.resume(X3m.System.Application)
    # the supervisor handles the registry's EXIT before this call, so it is restarted
    _children = Supervisor.which_children(X3m.System.Application)
    :ok = X3m.System.Test.Router.register_services()
  end

  # a handler that outlives its test would emit telemetry into the next test's handlers
  defp _await_exit(handler) do
    ref = Process.monitor(handler)
    assert_receive {:DOWN, ^ref, :process, ^handler, :normal}, 1_000
  end

  defp _new_message(service_name) do
    Message.new(service_name, raw_request: %{test_pid: self()})
  end
end
