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

  test "invoke local service" do
    msg = _new_message(:first)
    assert %Message{response: {:ok, :from_first}} = Dispatcher.dispatch(msg)
  end

  test "invoke private service" do
    msg = _new_message(:private_service)
    assert %Message{response: {:ok, :from_private}} = Dispatcher.dispatch(msg)
  end

  test "if service call is authorized" do
    assert Dispatcher.authorized?(_new_message(:first)) == true
    assert Dispatcher.authorized?(_new_message(:private_service)) == true
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
      assert_receive {^ref, :service_request_received}
      assert_receive {^ref, :invoking_service}
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
      refute_receive {^ref, :service_request_received}
      refute_receive {^ref, :invoking_service}
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
      assert_receive {^ref, :service_request_received}
      assert_receive {^ref, :invoking_service}
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
      refute_receive {^ref, :service_request_received}
      refute_receive {^ref, :invoking_service}
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
      refute_receive {^ref, :service_request_received}
      refute_receive {^ref, :invoking_service}
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
      refute_receive {^ref, :service_request_received}
      refute_receive {^ref, :invoking_service}
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
        [:x3m, :system, :service_request_received],
        [:x3m, :system, :invoking_service],
        [:x3m, :system, :service_responded]
      ],
      __MODULE__.telemetry_handler(service_name, parent, ref),
      nil
    )
  end

  def telemetry_handler(service_name, parent, ref) do
    fn
      [:x3m, :system, :discovering_service], _measurements, meta, _config ->
        assert %{caller_node: :nonode@nohost, message: %Message{service_name: ^service_name}} =
                 meta

        send(parent, {ref, :discovering_service})

      [:x3m, :system, :service_not_found], _measurements, meta, _config ->
        assert %{caller_node: :nonode@nohost, message: %Message{service_name: ^service_name}} =
                 meta

        send(parent, {ref, :service_not_found})

      [:x3m, :system, :service_found], _measurements, meta, _config ->
        assert %{caller_node: :nonode@nohost, message: %Message{service_name: ^service_name}} =
                 meta

        send(parent, {ref, :service_found})

      [:x3m, :system, :checking_if_service_call_is_authorized], _measurements, meta, _config ->
        assert %{caller_node: :nonode@nohost, message: %Message{service_name: ^service_name}} =
                 meta

        send(parent, {ref, :checking_if_service_call_is_authorized})

      [:x3m, :system, :service_request_received], _measurements, meta, _config ->
        assert %{service: ^service_name} = meta
        send(parent, {ref, :service_request_received})

      [:x3m, :system, :invoking_service], _measurements, meta, _config ->
        assert %{service: ^service_name} = meta
        send(parent, {ref, :invoking_service})

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

  defp _new_message(service_name) do
    Message.new(service_name, raw_request: %{test_pid: self()})
  end
end
