defmodule X3m.System.DispatcherTest do
  use ExUnit.Case, async: true
  alias X3m.System.{Message, Dispatcher}

  test "invoke unavailable service" do
    msg = _new_message(:wrong_service)
    assert %Message{response: {:service_unavailable, :wrong_service}} = Dispatcher.dispatch(msg)
  end

  test "invoke local service" do
    msg = _new_message(:first)
    assert %Message{response: {:ok, :from_first}} = Dispatcher.dispatch(msg)
  end

  test "invoke private service" do
    msg = _new_message(:private_service)
    assert %Message{response: {:ok, :from_private}} = Dispatcher.dispatch(msg)
  end

  defp _new_message(service_name) do
    Message.new(service_name, raw_request: %{test_pid: self()})
  end
end
