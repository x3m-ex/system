defmodule X3m.System.DispatcherTest do
  use ExUnit.Case, async: true
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

  defp _new_message(service_name) do
    Message.new(service_name, raw_request: %{test_pid: self()})
  end
end
