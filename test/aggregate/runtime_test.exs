defmodule X3m.System.Aggregate.RuntimeTest do
  use ExUnit.Case, async: false

  alias X3m.System.Aggregate.TestSupport
  alias X3m.System.Test.Account.{EventStore, MessageHandler, ReactiveMessageHandler}

  alias X3m.System.Test.Account.{
    UnloadOnEventsHandler,
    UnloadOnStateHandler,
    UnloadOnPartialStateHandler
  }

  alias X3m.System.Test.Account.TimeoutMessageHandler
  alias X3m.System.Test.Account.{SnapshotMessageHandler, StateStore}

  alias X3m.System.Test.Account.Events

  setup do
    EventStore.reset()
    :ok
  end

  describe "event-sourced lifecycle" do
    test "on_new_aggregate spawns, persists events, and replies {:created, id, version}" do
      account_id = _id()

      msg =
        TestSupport.command_message(:open_account, %{"id" => account_id, "owner_id" => "u1"})

      assert {:reply, replied} = MessageHandler.open_account(msg)
      assert {:created, account_id, 0} == replied.response

      assert [{%Events.Opened{owner_id: "u1"}, 0, %{message_id: _}}] =
               EventStore.dump("accounts-" <> account_id)
    end

    test "_unload/1 terminates the live process and clears it from the registry" do
      account_id = _id()

      {:reply, _} =
        :open_account
        |> TestSupport.command_message(%{"id" => account_id, "owner_id" => "u1"})
        |> MessageHandler.open_account()

      assert {:ok, pid} = _registry_get(account_id)
      assert Process.alive?(pid)

      :ok = _unload(account_id)

      assert :error == _registry_get(account_id)
      refute Process.alive?(pid)
    end

    test "on_aggregate on a cold (persisted) id rehydrates from the stream and runs the command" do
      account_id = _id()

      {:reply, _} =
        :open_account
        |> TestSupport.command_message(%{"id" => account_id, "owner_id" => "u1"})
        |> MessageHandler.open_account()

      :ok = _unload(account_id)

      {:reply, replied} =
        :deposit
        |> TestSupport.command_message(%{"id" => account_id, "amount" => 100})
        |> MessageHandler.deposit()

      assert {:ok, 1} = replied.response

      assert [_opened, {%Events.Deposited{amount: 100}, 1, _}] =
               EventStore.dump("accounts-" <> account_id)
    end

    test "on_new_aggregate fails when the aggregate is already hot in memory" do
      account_id = _id()

      {:reply, _} =
        :open_account
        |> TestSupport.command_message(%{"id" => account_id, "owner_id" => "u1"})
        |> MessageHandler.open_account()

      {:reply, replied} =
        :open_account
        |> TestSupport.command_message(%{"id" => account_id, "owner_id" => "u1"})
        |> MessageHandler.open_account()

      assert {:error, :key_already_registered, _pid} = replied.response
    end

    test "on_new_aggregate fails when the aggregate already exists in persistence" do
      account_id = _id()

      {:reply, _} =
        :open_account
        |> TestSupport.command_message(%{"id" => account_id, "owner_id" => "u1"})
        |> MessageHandler.open_account()

      :ok = _unload(account_id)

      {:reply, replied} =
        :open_account
        |> TestSupport.command_message(%{"id" => account_id, "owner_id" => "u1"})
        |> MessageHandler.open_account()

      assert {:error, :wrong_expected_version, 0} = replied.response
      Process.sleep(50)
      assert :error == _registry_get(account_id)
    end

    test "on_aggregate fails when the aggregate does not exist" do
      account_id = _id()

      {:reply, replied} =
        :deposit
        |> TestSupport.command_message(%{"id" => account_id, "amount" => 10})
        |> MessageHandler.deposit()

      assert {:error, :not_found} = replied.response
    end

    test "on_maybe_new_aggregate creates when absent, updates owner when changed, no-ops when unchanged" do
      account_id = _id()
      stream = "accounts-" <> account_id

      # absent -> creates the aggregate and sets the owner
      {:reply, created} =
        :ensure_account
        |> TestSupport.command_message(%{"id" => account_id, "owner_id" => "u1"})
        |> MessageHandler.ensure_account()

      assert {:created, ^account_id, 0} = created.response
      assert [{%Events.Opened{owner_id: "u1"}, 0, _}] = EventStore.dump(stream)

      # present, same owner -> no-op (no new event, version unchanged)
      {:reply, unchanged} =
        :ensure_account
        |> TestSupport.command_message(%{"id" => account_id, "owner_id" => "u1"})
        |> MessageHandler.ensure_account()

      assert {:ok, 0} = unchanged.response
      assert 1 == length(EventStore.dump(stream))

      # present, different owner -> works on the existing aggregate (OwnerChanged)
      {:reply, changed} =
        :ensure_account
        |> TestSupport.command_message(%{"id" => account_id, "owner_id" => "u2"})
        |> MessageHandler.ensure_account()

      assert {:ok, 1} = changed.response

      assert [
               {%Events.Opened{owner_id: "u1"}, 0, _},
               {%Events.OwnerChanged{owner_id: "u2"}, 1, _}
             ] =
               EventStore.dump(stream)
    end

    test "the same message handled twice on a hot aggregate is deduped (no second event)" do
      account_id = _id()

      {:reply, _} =
        :open_account
        |> TestSupport.command_message(%{"id" => account_id, "owner_id" => "u1"})
        |> MessageHandler.open_account()

      deposit = TestSupport.command_message(:deposit, %{"id" => account_id, "amount" => 50})

      {:reply, first} = MessageHandler.deposit(deposit)
      {:reply, second} = MessageHandler.deposit(deposit)

      assert {:ok, _} = first.response
      assert {:ok, _} = second.response

      assert 1 == length(_deposits("accounts-" <> account_id))
    end

    test "idempotency survives a rehydrate (id read from event metadata on replay)" do
      account_id = _id()

      {:reply, _} =
        :open_account
        |> TestSupport.command_message(%{"id" => account_id, "owner_id" => "u1"})
        |> MessageHandler.open_account()

      deposit = TestSupport.command_message(:deposit, %{"id" => account_id, "amount" => 50})
      {:reply, _} = MessageHandler.deposit(deposit)

      :ok = _unload(account_id)

      {:reply, replayed} = MessageHandler.deposit(deposit)
      assert {:ok, _} = replayed.response

      assert 1 == length(_deposits("accounts-" <> account_id))
    end

    test "dry_run: true commits nothing and rolls back" do
      account_id = _id()

      {:reply, _} =
        :open_account
        |> TestSupport.command_message(%{"id" => account_id, "owner_id" => "u1"})
        |> MessageHandler.open_account()

      before = EventStore.dump("accounts-" <> account_id)

      msg =
        :deposit
        |> X3m.System.Message.new(
          raw_request: %{"id" => account_id, "amount" => 100},
          dry_run: true
        )

      {:reply, replied} = MessageHandler.deposit(msg)

      # on_aggregate dry_run echoes {:ok, dry_run_version, version} (both the current version)
      assert {:ok, 0, 0} == replied.response
      assert before == EventStore.dump("accounts-" <> account_id)
    end

    test "dry_run: :verbose returns the events without persisting them" do
      account_id = _id()

      {:reply, _} =
        :open_account
        |> TestSupport.command_message(%{"id" => account_id, "owner_id" => "u1"})
        |> MessageHandler.open_account()

      before = EventStore.dump("accounts-" <> account_id)

      msg =
        :deposit
        |> X3m.System.Message.new(
          raw_request: %{"id" => account_id, "amount" => 100},
          dry_run: :verbose
        )

      {:reply, replied} = MessageHandler.deposit(msg)

      assert {:ok, [%Events.Deposited{amount: 100}], _version} = replied.response
      assert before == EventStore.dump("accounts-" <> account_id)
    end
  end

  describe "save_events/1 override" do
    test "reacts to produced events and filters which ones persist" do
      # registered name auto-clears when this (async: false) test process exits
      Process.register(self(), :reactive_test_observer)

      account_id = _id()

      {:reply, _} =
        :open_account
        |> TestSupport.command_message(%{"id" => account_id, "owner_id" => "u1"})
        |> ReactiveMessageHandler.open_account()

      # withdraw more than the (zero) balance -> aggregate emits WithdrawalRejected with an error
      {:reply, replied} =
        :withdraw
        |> TestSupport.command_message(%{"id" => account_id, "amount" => 999})
        |> ReactiveMessageHandler.withdraw()

      assert {:error, :insufficient_funds} == replied.response

      # the override reacted with the emitted event...
      assert_received {:reacted, [%Events.WithdrawalRejected{amount: 999}]}

      # ...but filtered it out of persistence (only the Opened event remains)
      rejected =
        ("reactive-accounts-" <> account_id)
        |> EventStore.dump()
        |> Enum.filter(fn {event, _number, _meta} ->
          match?(%Events.WithdrawalRejected{}, event)
        end)

      assert [] == rejected
    end
  end

  describe "save failures" do
    test "a generic save_events error kills the aggregate and returns the error" do
      account_id = _id()
      EventStore.fail("accounts-" <> account_id, {:error, :boom})

      {:reply, replied} =
        :open_account
        |> TestSupport.command_message(%{"id" => account_id, "owner_id" => "u1"})
        |> MessageHandler.open_account()

      assert {:error, :boom} == replied.response

      Process.sleep(50)
      assert :error == _registry_get(account_id)
    end
  end

  describe "unload_aggregate_on" do
    test "events rule schedules a delayed teardown" do
      account_id = _id()

      {:reply, _} =
        :open_account
        |> TestSupport.command_message(%{"id" => account_id, "owner_id" => "u1"})
        |> UnloadOnEventsHandler.open_account()

      {:reply, _} =
        :deposit
        |> TestSupport.command_message(%{"id" => account_id, "amount" => 10})
        |> UnloadOnEventsHandler.deposit()

      assert {:ok, _pid} = _registry_get(account_id)
      Process.sleep(80)
      assert :error == _registry_get(account_id)
    end

    test "state rule :unload tears the process down on close" do
      account_id = _id()

      {:reply, _} =
        :open_account
        |> TestSupport.command_message(%{"id" => account_id, "owner_id" => "u1"})
        |> UnloadOnStateHandler.open_account()

      {:reply, _} =
        :close_account
        |> TestSupport.command_message(%{"id" => account_id}, %{invoked_by: %{admin?: true}})
        |> UnloadOnStateHandler.close_account()

      Process.sleep(50)
      assert :error == _registry_get(account_id)
    end

    test "state rule {:in, ms} delays teardown; :skip keeps the process" do
      big = _id()

      {:reply, _} =
        :open_account
        |> TestSupport.command_message(%{"id" => big, "owner_id" => "u1"})
        |> UnloadOnStateHandler.open_account()

      {:reply, _} =
        :deposit
        |> TestSupport.command_message(%{"id" => big, "amount" => 5_000})
        |> UnloadOnStateHandler.deposit()

      assert {:ok, _pid} = _registry_get(big)
      Process.sleep(80)
      assert :error == _registry_get(big)

      small = _id()

      {:reply, _} =
        :open_account
        |> TestSupport.command_message(%{"id" => small, "owner_id" => "u1"})
        |> UnloadOnStateHandler.open_account()

      {:reply, _} =
        :deposit
        |> TestSupport.command_message(%{"id" => small, "amount" => 10})
        |> UnloadOnStateHandler.deposit()

      Process.sleep(80)
      assert {:ok, _pid} = _registry_get(small)
    end

    test "a FunctionClauseError in the state fn is rescued to :skip" do
      account_id = _id()

      {:reply, _} =
        :open_account
        |> TestSupport.command_message(%{"id" => account_id, "owner_id" => "u1"})
        |> UnloadOnPartialStateHandler.open_account()

      {:reply, _} =
        :deposit
        |> TestSupport.command_message(%{"id" => account_id, "amount" => 10})
        |> UnloadOnPartialStateHandler.deposit()

      Process.sleep(50)
      assert {:ok, _pid} = _registry_get(account_id)
    end
  end

  describe "commit timeout" do
    test "offloads the aggregate, persists the events, and a retry rehydrates correct state" do
      account_id = _id()
      stream = "timeout-accounts-" <> account_id

      {:reply, _} =
        :open_account
        |> TestSupport.command_message(%{"id" => account_id, "owner_id" => "u1"})
        |> TimeoutMessageHandler.open_account()

      # make save_events slower than the 50ms commit_timeout
      EventStore.delay(stream, 200)

      deposit = TestSupport.command_message(:deposit, %{"id" => account_id, "amount" => 100})

      # Documented contract: on a commit timeout the handler's hard `{:ok, _} = commit(...)`
      # match fails (commit/4 returns :transaction_timeout), so the caller crashes -> the client
      # sees a timeout (no reply). This is intended; recovery is via offload + retry below.
      # (A future, configurable router-level retry on such timeouts would be safe because
      # idempotency reconciles the already-persisted events.)
      crashed =
        try do
          TimeoutMessageHandler.deposit(deposit)
          false
        rescue
          MatchError -> true
        catch
          :exit, _ -> true
        end

      Process.sleep(250)

      # 1) events were actually persisted despite the timeout
      assert [_opened, {%Events.Deposited{amount: 100}, 1, _}] = EventStore.dump(stream)
      # 2) the aggregate was offloaded (cleared from the registry)
      assert :error == _registry_get(account_id)

      # 3) a retry rehydrates from the persisted events (not stale memory) and succeeds
      EventStore.delay(stream, 0)

      {:reply, retried} =
        :deposit
        |> TestSupport.command_message(%{"id" => account_id, "amount" => 5})
        |> TimeoutMessageHandler.deposit()

      assert {:ok, _version} = retried.response
      # the timed-out-but-persisted 100, plus the retried 5
      assert 2 == length(_deposits(stream))
      # the timed-out command crashed the caller (client-visible timeout) — intended behavior
      assert true == crashed
    end
  end

  describe "non-event-sourced (standard save/load) lifecycle" do
    setup do
      StateStore.reset()
      :ok
    end

    test "save_state persists the full state row (client_state + version) on commit" do
      account_id = _id()

      {:reply, _} =
        :open_account
        |> TestSupport.command_message(%{"id" => account_id, "owner_id" => "u1"})
        |> SnapshotMessageHandler.open_account()

      {:reply, _} =
        :deposit
        |> TestSupport.command_message(%{"id" => account_id, "amount" => 250})
        |> SnapshotMessageHandler.deposit()

      assert {:ok, {state, version}} = StateStore.get(account_id)
      assert 250 == state.balance
      assert "u1" == state.owner_id
      assert 1 == version
    end

    test "a cold command loads state via when_pid_is_not_registered and runs against it" do
      account_id = _id()

      {:reply, _} =
        :open_account
        |> TestSupport.command_message(%{"id" => account_id, "owner_id" => "u1"})
        |> SnapshotMessageHandler.open_account()

      {:reply, _} =
        :deposit
        |> TestSupport.command_message(%{"id" => account_id, "amount" => 250})
        |> SnapshotMessageHandler.deposit()

      # drop the live process; only the StateStore row remains
      :ok = _unload(account_id)

      {:reply, replied} =
        :deposit
        |> TestSupport.command_message(%{"id" => account_id, "amount" => 100})
        |> SnapshotMessageHandler.deposit()

      assert {:ok, _version} = replied.response
      assert {:ok, {state, _version}} = StateStore.get(account_id)
      assert 350 == state.balance
    end

    test "dry_run leaves the state store unchanged (same as the event-sourced store)" do
      account_id = _id()

      {:reply, _} =
        :open_account
        |> TestSupport.command_message(%{"id" => account_id, "owner_id" => "u1"})
        |> SnapshotMessageHandler.open_account()

      before = StateStore.get(account_id)

      msg =
        :deposit
        |> X3m.System.Message.new(
          raw_request: %{"id" => account_id, "amount" => 100},
          dry_run: true
        )

      {:reply, _replied} = SnapshotMessageHandler.deposit(msg)

      assert before == StateStore.get(account_id)
    end
  end

  defp _deposits(stream_name) do
    stream_name
    |> EventStore.dump()
    |> Enum.filter(fn {event, _number, _meta} -> match?(%Events.Deposited{}, event) end)
  end

  defp _unload(account_id) do
    X3m.System.Test.Account.Aggregate
    |> X3m.System.AggregatePidFacade.name()
    |> X3m.System.AggregatePidFacade.exit_process(account_id, :unload_for_test)

    Process.sleep(50)
    :ok
  end

  defp _registry_get(account_id) do
    X3m.System.Test.Account.Aggregate
    |> X3m.System.AggregateRegistry.name()
    |> X3m.System.AggregateRegistry.get(account_id)
  end

  defp _id(), do: UUID.uuid4()
end
