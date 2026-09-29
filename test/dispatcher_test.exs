defmodule X3m.System.DispatcherTest do
  use ExUnit.Case, async: false
  alias X3m.System.{Message, Dispatcher}

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

  # a handler that outlives its test would emit telemetry into the next test's handlers
  defp _await_exit(handler) do
    ref = Process.monitor(handler)
    assert_receive {:DOWN, ^ref, :process, ^handler, :normal}, 1_000
  end

  defp _new_message(service_name) do
    Message.new(service_name, raw_request: %{test_pid: self()})
  end
end
