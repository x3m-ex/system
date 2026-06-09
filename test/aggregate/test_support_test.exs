defmodule X3m.System.Aggregate.TestSupportTest do
  use ExUnit.Case, async: true
  alias X3m.System.Aggregate
  alias X3m.System.Aggregate.TestSupport
  alias X3m.System.Test.Account.Aggregate, as: Account
  alias X3m.System.Test.Account.{State, Events}

  doctest X3m.System.Aggregate.TestSupport

  describe "command_message/3" do
    test "builds a message with raw_request and assigns" do
      msg =
        TestSupport.command_message(:deposit, %{"amount" => 10}, %{invoked_by: %{user_id: "u1"}})

      assert msg.service_name == :deposit
      assert msg.raw_request == %{"amount" => 10}
      assert msg.assigns == %{invoked_by: %{user_id: "u1"}}
    end

    test "defaults raw_request and assigns to empty maps" do
      msg = TestSupport.command_message(:ping)
      assert msg.raw_request == %{}
      assert msg.assigns == %{}
    end
  end

  describe "state_from_events/3 (the given step)" do
    test "replays events into client_state and sets version to last index" do
      state =
        TestSupport.state_from_events(Account, [
          %Events.Opened{id: "a1", owner_id: "u1"},
          %Events.Deposited{id: "a1", amount: 100}
        ])

      assert %Aggregate.State{
               version: 1,
               client_state: %State{id: "a1", owner_id: "u1", balance: 100}
             } = state
    end

    test "honors an explicit :version" do
      state =
        TestSupport.state_from_events(Account, [%Events.Opened{id: "a1", owner_id: "u1"}],
          version: 7
        )

      assert state.version == 7
    end
  end

  describe "apply_events/4 (the then step)" do
    test "folds new events onto an existing state and bumps the version" do
      given = TestSupport.state_from_events(Account, [%Events.Opened{id: "a1", owner_id: "u1"}])

      applied =
        TestSupport.apply_events(Account, given, [%Events.Deposited{id: "a1", amount: 40}])

      assert applied.client_state.balance == 40
      assert applied.version == given.version + 1
    end
  end
end
