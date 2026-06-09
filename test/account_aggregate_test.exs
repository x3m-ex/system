defmodule X3m.System.Test.AccountAggregateTest do
  use ExUnit.Case, async: true
  alias X3m.System.{Aggregate, Message}
  alias X3m.System.Aggregate.TestSupport
  alias X3m.System.Test.Account.Aggregate, as: Account
  alias X3m.System.Test.Account.{State, Events}

  test "initial_state/1 wraps the account's starting client state" do
    assert %Aggregate.State{version: -1, client_state: %State{balance: 0, closed?: false}} =
             Aggregate.initial_state(Account)
  end

  describe "open_account" do
    test "emits Opened and replies :created; applied state has id and owner" do
      # given
      state = Aggregate.initial_state(Account)
      # when
      msg = TestSupport.command_message(:open_account, %{"id" => "a1", "owner_id" => "u1"})

      assert {:block,
              %Message{
                events: [%Events.Opened{id: "a1", owner_id: "u1"}] = events,
                response: {:created, "a1"},
                halted?: true
              }, _} = Account.open_account(msg, state)

      # then
      applied = TestSupport.apply_events(Account, state, events)
      assert applied.client_state.id == "a1"
      assert applied.client_state.owner_id == "u1"
    end

    test "halts with a validation_error when owner_id is missing" do
      state = Aggregate.initial_state(Account)
      msg = TestSupport.command_message(:open_account, %{"id" => "a1"})

      assert {:noblock,
              %Message{halted?: true, response: {:validation_error, _changeset}, events: []},
              ^state} =
               Account.open_account(msg, state)
    end
  end

  describe "deposit" do
    test "emits Deposited; applied state's balance grows" do
      # given
      state = TestSupport.state_from_events(Account, [%Events.Opened{id: "a1", owner_id: "u1"}])
      assert state.client_state.balance == 0
      # when
      msg = TestSupport.command_message(:deposit, %{"id" => "a1", "amount" => 100})

      assert {:block, %Message{events: [%Events.Deposited{amount: 100}] = events, response: :ok},
              _} =
               Account.deposit(msg, state)

      # then
      applied = TestSupport.apply_events(Account, state, events)
      assert applied.client_state.balance == 100
    end

    test "halts with a validation_error when amount is not positive" do
      state = TestSupport.state_from_events(Account, [%Events.Opened{id: "a1", owner_id: "u1"}])
      msg = TestSupport.command_message(:deposit, %{"id" => "a1", "amount" => 0})

      assert {:noblock, %Message{halted?: true, response: {:validation_error, _}, events: []},
              ^state} =
               Account.deposit(msg, state)
    end

    test "halts with a validation_error when the account is closed (state-aware validation)" do
      # given a closed account
      state =
        TestSupport.state_from_events(Account, [
          %Events.Opened{id: "a1", owner_id: "u1"},
          %Events.Closed{id: "a1"}
        ])

      assert state.client_state.closed? == true
      # when / then
      msg = TestSupport.command_message(:deposit, %{"id" => "a1", "amount" => 50})

      assert {:noblock, %Message{halted?: true, response: {:validation_error, _}, events: []},
              ^state} =
               Account.deposit(msg, state)
    end
  end

  describe "withdraw" do
    test "within balance emits Withdrawn; applied balance drops" do
      state =
        TestSupport.state_from_events(Account, [
          %Events.Opened{id: "a1", owner_id: "u1"},
          %Events.Deposited{id: "a1", amount: 100}
        ])

      assert state.client_state.balance == 100
      msg = TestSupport.command_message(:withdraw, %{"id" => "a1", "amount" => 60})

      assert {:block, %Message{events: [%Events.Withdrawn{amount: 60}] = events, response: :ok},
              _} =
               Account.withdraw(msg, state)

      applied = TestSupport.apply_events(Account, state, events)
      assert applied.client_state.balance == 40
    end

    test "beyond balance records WithdrawalRejected AND returns an error (events with error)" do
      state =
        TestSupport.state_from_events(Account, [
          %Events.Opened{id: "a1", owner_id: "u1"},
          %Events.Deposited{id: "a1", amount: 100}
        ])

      assert state.client_state.balance == 100
      msg = TestSupport.command_message(:withdraw, %{"id" => "a1", "amount" => 150})

      assert {:block,
              %Message{
                events: [%Events.WithdrawalRejected{amount: 150, balance: 100}] = events,
                response: {:error, :insufficient_funds}
              }, _} = Account.withdraw(msg, state)

      # the rejection is recorded in state; balance is untouched
      applied = TestSupport.apply_events(Account, state, events)
      assert applied.client_state.balance == 100
      assert applied.client_state.highest_rejected_withdrawal == 150
    end
  end

  describe "close_account (instance authorization, multi-event)" do
    setup do
      # an account owned by "u1" holding 100
      state =
        TestSupport.state_from_events(Account, [
          %Events.Opened{id: "a1", owner_id: "u1"},
          %Events.Deposited{id: "a1", amount: 100}
        ])

      assert state.client_state.owner_id == "u1"
      assert state.client_state.balance == 100
      {:ok, state: state}
    end

    test "an admin may close; it returns the balance then closes", %{state: state} do
      msg = TestSupport.command_message(:close_account, %{}, %{invoked_by: %{admin?: true}})

      assert {:block,
              %Message{
                events: [%Events.Withdrawn{amount: 100}, %Events.Closed{}] = events,
                response: :ok
              }, _} = Account.close_account(msg, state)

      applied = TestSupport.apply_events(Account, state, events)
      assert applied.client_state.balance == 0
      assert applied.client_state.closed? == true
    end

    test "the owner may close their own account", %{state: state} do
      msg = TestSupport.command_message(:close_account, %{}, %{invoked_by: %{user_id: "u1"}})

      assert {:block,
              %Message{
                events: [%Events.Withdrawn{amount: 100}, %Events.Closed{}] = events,
                response: :ok
              }, _} = Account.close_account(msg, state)

      applied = TestSupport.apply_events(Account, state, events)
      assert applied.client_state.balance == 0
      assert applied.client_state.closed? == true
    end

    test "anyone else is forbidden; no event, state unchanged", %{state: state} do
      msg = TestSupport.command_message(:close_account, %{}, %{invoked_by: %{user_id: "u2"}})

      assert {:noblock, %Message{events: [], response: {:error, :forbidden}}, ^state} =
               Account.close_account(msg, state)
    end
  end

  describe "idempotency" do
    test "a message whose id was already processed returns :ok, no events, and warns" do
      state = TestSupport.state_from_events(Account, [%Events.Opened{id: "a1", owner_id: "u1"}])
      msg = TestSupport.command_message(:deposit, %{"id" => "a1", "amount" => 50})

      processed = %Aggregate.State{
        state
        | processed_messages: MapSet.put(state.processed_messages, msg.id)
      }

      {result, log} = ExUnit.CaptureLog.with_log(fn -> Account.deposit(msg, processed) end)

      assert {:noblock, %Message{response: :ok, events: []}, ^processed} = result
      assert log =~ "already processed"
    end
  end
end
