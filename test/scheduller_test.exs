defmodule X3m.System.SchedullerTest do
  use ExUnit.Case, async: true
  require Logger
  alias X3m.System.Test.Scheduller
  alias X3m.System.Message

  setup do
    {:ok, _} = Scheduller.start_link(self())
    assert_receive {:load_alarms, nil, _load_until}
    :ok
  end

  describe "Scheduller.dispatch/2" do
    test "accepts alarm in miliseconds" do
      %{id: id} = msg = Message.new(:wrong_service)
      :ok = Scheduller.dispatch(msg, "aggregate_id", in: 50)
      assert_receive {:save_alarm, %Message{id: ^id}, "aggregate_id"}

      assert_receive {:service_responded,
                      %Message{id: id, response: {:service_unavailable, :wrong_service}}}

      assert_receive {:service_responded,
                      %Message{
                        id: id,
                        assigns: %{redelivered?: true},
                        response: {:service_unavailable, :wrong_service}
                      }},
                     200
    end

    test "accepts alarm in DateTime" do
      %{id: id} = msg = Message.new(:wrong_service)
      dispatch_at = DateTime.utc_now() |> DateTime.add(50, :millisecond)
      :ok = Scheduller.dispatch(msg, "aggregate_id", at: dispatch_at)

      assert_receive {:save_alarm, %Message{id: ^id, assigns: %{dispatch_at: dispatch_at}},
                      "aggregate_id"}

      assert_receive {:service_responded,
                      %Message{id: id, response: {:service_unavailable, :wrong_service}}}

      assert_receive {:service_responded,
                      %Message{
                        id: id,
                        assigns: %{redelivered?: true},
                        response: {:service_unavailable, :wrong_service}
                      }},
                     200
    end
  end
end
