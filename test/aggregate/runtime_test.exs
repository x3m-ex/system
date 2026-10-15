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
  alias X3m.System.Test.Account.{BrokenAggregate, BrokenMessageHandler}
  alias X3m.System.Test.Account.AbandoningLoadHandler
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

    test "a duplicate create leaves the live aggregate registered, serving and alone" do
      account_id = _id()

      {:reply, _opened} =
        :open_account
        |> TestSupport.command_message(%{"id" => account_id, "owner_id" => "u1"})
        |> MessageHandler.open_account()

      {:ok, live_pid} = _registry_get(account_id)
      aggregates_before = _aggregate_pids()

      {:reply, duplicate} =
        :open_account
        |> TestSupport.command_message(%{"id" => account_id, "owner_id" => "u1"})
        |> MessageHandler.open_account()

      assert {:error, :key_already_registered, ^live_pid} = duplicate.response
      assert aggregates_before == _aggregate_pids()
      assert {:ok, live_pid} == _registry_get(account_id)

      {:reply, deposited} =
        :deposit
        |> TestSupport.command_message(%{"id" => account_id, "amount" => 100})
        |> MessageHandler.deposit()

      assert {:ok, 1} == deposited.response
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

      assert {:error, :wrong_expected_version, -1} = replied.response
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

    test "on_aggregate on a missing aggregate logs a warning" do
      account_id = _id()

      log =
        ExUnit.CaptureLog.capture_log(fn ->
          {:reply, replied} =
            :deposit
            |> TestSupport.command_message(%{"id" => account_id, "amount" => 10})
            |> MessageHandler.deposit()

          assert {:error, :not_found} == replied.response
        end)

      assert log =~ "[warning] No events found for aggregate: #{account_id}"
    end

    test "on_maybe_new_aggregate creating a missing aggregate logs no warning" do
      account_id = _id()

      log =
        ExUnit.CaptureLog.capture_log(fn ->
          {:reply, created} =
            :ensure_account
            |> TestSupport.command_message(%{"id" => account_id, "owner_id" => "u1"})
            |> MessageHandler.ensure_account()

          assert {:created, account_id, 0} == created.response
        end)

      assert log =~ "[debug] No events found for aggregate: #{account_id}"
      refute log =~ "[warning]"
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

  describe "dry run on a new aggregate" do
    test "a valid dry run tears its aggregate down without a warning" do
      account_id = _id()
      aggregates_before = _aggregate_pids()

      log =
        ExUnit.CaptureLog.capture_log(fn ->
          {:reply, replied} =
            :open_account
            |> X3m.System.Message.new(
              raw_request: %{"id" => account_id, "owner_id" => "u1"},
              dry_run: true
            )
            |> MessageHandler.open_account()

          assert {:ok, -1} == replied.response
          assert :error == _registry_get(account_id)
        end)

      assert aggregates_before == _aggregate_pids()
      assert [] == EventStore.dump("accounts-" <> account_id)
      refute log =~ "[warning]"
    end

    test "a valid verbose dry run tears its aggregate down without a warning" do
      account_id = _id()
      aggregates_before = _aggregate_pids()

      log =
        ExUnit.CaptureLog.capture_log(fn ->
          {:reply, replied} =
            :open_account
            |> X3m.System.Message.new(
              raw_request: %{"id" => account_id, "owner_id" => "u1"},
              dry_run: :verbose
            )
            |> MessageHandler.open_account()

          assert {:ok, [%Events.Opened{owner_id: "u1"}], -1} = replied.response
          assert :error == _registry_get(account_id)
        end)

      assert aggregates_before == _aggregate_pids()
      refute log =~ "[warning]"
    end

    test "a rejected dry run tears its aggregate down without a warning" do
      account_id = _id()
      aggregates_before = _aggregate_pids()

      log =
        ExUnit.CaptureLog.capture_log(fn ->
          {:reply, replied} =
            :open_account
            |> X3m.System.Message.new(raw_request: %{"id" => account_id}, dry_run: true)
            |> MessageHandler.open_account()

          assert {:validation_error,
                  %Ecto.Changeset{errors: [owner_id: {"can't be blank", [validation: :required]}]}} =
                   replied.response

          assert :error == _registry_get(account_id)
        end)

      assert aggregates_before == _aggregate_pids()
      refute log =~ "[warning]"
    end

    for dry_run <- [true, :verbose] do
      test "repeated #{inspect(dry_run)} dry runs keep the aggregate supervisor and its children" do
        sup_before = _aggregate_sup()
        aggregates_before = _aggregate_pids()

        _tear_down_past_restart_intensity(fn ->
          account_id = _id()

          {:reply, _replied} =
            :open_account
            |> X3m.System.Message.new(
              raw_request: %{"id" => account_id, "owner_id" => "u1"},
              dry_run: unquote(dry_run)
            )
            |> MessageHandler.open_account()

          assert :error == _registry_get(account_id)
        end)

        assert sup_before == _aggregate_sup()
        assert aggregates_before == _aggregate_pids()
      end
    end

    for {kind, raw_request, dry_run} <- [
          {"valid", %{"owner_id" => "u1"}, true},
          {"valid verbose", %{"owner_id" => "u1"}, :verbose},
          {"rejected", %{}, true}
        ] do
      test "a real creation right after a #{kind} dry run on the same id succeeds" do
        for _run <- 1..20 do
          account_id = _id()

          {:reply, _dry_run} =
            :open_account
            |> X3m.System.Message.new(
              raw_request: Map.put(unquote(Macro.escape(raw_request)), "id", account_id),
              dry_run: unquote(dry_run)
            )
            |> MessageHandler.open_account()

          {:reply, created} =
            :open_account
            |> TestSupport.command_message(%{"id" => account_id, "owner_id" => "u1"})
            |> MessageHandler.open_account()

          assert {:created, account_id, 0} == created.response
        end
      end
    end

    test "a rejected real creation logs at debug without a warning" do
      account_id = _id()

      log =
        ExUnit.CaptureLog.capture_log(fn ->
          {:reply, _replied} =
            :open_account
            |> TestSupport.command_message(%{"id" => account_id})
            |> MessageHandler.open_account()

          assert :error == _registry_get(account_id)
        end)

      assert log =~ "[debug] New aggregate creation failed"
      refute log =~ "[warning]"
    end
  end

  describe "when_pid_is_not_registered/3 override" do
    test "can tear down the aggregate it spawned without stopping the pid facade" do
      account_id = _id()
      facade_before = _pid_facade()
      aggregates_before = _aggregate_pids()

      {:reply, replied} =
        :deposit
        |> TestSupport.command_message(%{"id" => account_id, "amount" => 1})
        |> AbandoningLoadHandler.deposit()

      assert {:error, :not_found} == replied.response
      assert facade_before == _pid_facade()
      assert :error == _registry_get(account_id)
      assert aggregates_before == _aggregate_pids()
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
    test "a not_found save_events error on a live aggregate is not logged as a missing aggregate" do
      account_id = _id()

      {:reply, _opened} =
        :open_account
        |> TestSupport.command_message(%{"id" => account_id, "owner_id" => "u1"})
        |> MessageHandler.open_account()

      EventStore.fail("accounts-" <> account_id, {:error, :not_found})

      log =
        ExUnit.CaptureLog.capture_log(fn ->
          {:reply, replied} =
            :deposit
            |> TestSupport.command_message(%{"id" => account_id, "amount" => 10})
            |> MessageHandler.deposit()

          assert {:error, :not_found} == replied.response
        end)

      assert log =~ "[error] Error saving events {:error, :not_found}"
      refute log =~ "No events found for aggregate"
    end

    test "a generic save_events error kills the aggregate and returns the error" do
      account_id = _id()
      EventStore.fail("accounts-" <> account_id, {:error, :boom})

      {:reply, replied} =
        :open_account
        |> TestSupport.command_message(%{"id" => account_id, "owner_id" => "u1"})
        |> MessageHandler.open_account()

      assert {:error, :boom} == replied.response
      assert :error == _registry_get(account_id)
    end

    test "a save_events error ends the aggregate before the caller gets the error, so a retry replays persisted events" do
      account_id = _id()

      {:reply, _opened} =
        :open_account
        |> TestSupport.command_message(%{"id" => account_id, "owner_id" => "u1"})
        |> MessageHandler.open_account()

      {:ok, stale_pid} = _registry_get(account_id)
      EventStore.fail_after_persist("accounts-" <> account_id, {:error, :boom})

      {:reply, failed} =
        :deposit
        |> TestSupport.command_message(%{"id" => account_id, "amount" => 100})
        |> MessageHandler.deposit()

      assert {:error, :boom} == failed.response
      refute Process.alive?(stale_pid)

      assert :error == _registry_get(account_id)

      {:reply, retried} =
        :withdraw
        |> TestSupport.command_message(%{"id" => account_id, "amount" => 100})
        |> MessageHandler.withdraw()

      assert {:ok, 2} == retried.response
      assert {:ok, fresh_pid} = _registry_get(account_id)
      refute stale_pid == fresh_pid
    end

    test "a save_events error leaves no aggregate process behind" do
      account_id = _id()
      EventStore.fail("accounts-" <> account_id, {:error, :boom})
      aggregates_before = _aggregate_pids()

      {:reply, _replied} =
        :open_account
        |> TestSupport.command_message(%{"id" => account_id, "owner_id" => "u1"})
        |> MessageHandler.open_account()

      assert :error == _registry_get(account_id)
      assert aggregates_before == _aggregate_pids()
    end

    test "repeated save_events errors keep the aggregate supervisor and its children" do
      sup_before = _aggregate_sup()
      aggregates_before = _aggregate_pids()

      _tear_down_past_restart_intensity(fn ->
        account_id = _id()
        EventStore.fail("accounts-" <> account_id, {:error, :boom})

        {:reply, _replied} =
          :open_account
          |> TestSupport.command_message(%{"id" => account_id, "owner_id" => "u1"})
          |> MessageHandler.open_account()

        assert :error == _registry_get(account_id)
      end)

      assert sup_before == _aggregate_sup()
      assert aggregates_before == _aggregate_pids()
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

    test "repeated commit timeouts keep the aggregate supervisor and its children" do
      sup_before = _aggregate_sup()
      aggregates_before = _aggregate_pids()

      _tear_down_past_restart_intensity(fn ->
        account_id = _id()
        :ok = _open_with_slow_saves(account_id)
        :ok = _time_out_deposit(account_id)
        :ok = _await_unregistered(account_id)
      end)

      assert sup_before == _aggregate_sup()
      assert aggregates_before == _aggregate_pids()
    end

    test "a commit timeout is logged as a warning" do
      account_id = _id()

      log =
        ExUnit.CaptureLog.capture_log(fn ->
          :ok = _open_with_slow_saves(account_id)
          :ok = _time_out_deposit(account_id)
          :ok = _await_unregistered(account_id)
        end)

      assert log =~ "[warning] Commit timed out after 50ms"
      refute log =~ "[error]"
    end
  end

  describe "aggregate crash" do
    test "an exception raised by the aggregate leaves no aggregate process behind" do
      account_id = _id()
      aggregates_before = _aggregate_pids()

      {:reply, _opened} =
        :open_account
        |> TestSupport.command_message(%{"id" => account_id, "owner_id" => "u1"})
        |> MessageHandler.open_account()

      {:ok, crashed_pid} = _registry_get(account_id)

      log =
        ExUnit.CaptureLog.capture_log(fn ->
          :ok = _explode(account_id)
          :ok = _await_unregistered(account_id)
        end)

      assert log =~ "aggregate exploded"
      refute Process.alive?(crashed_pid)
      assert aggregates_before == _aggregate_pids()
    end

    test "the next command after an aggregate crash rehydrates from persisted events" do
      account_id = _id()

      {:reply, _opened} =
        :open_account
        |> TestSupport.command_message(%{"id" => account_id, "owner_id" => "u1"})
        |> MessageHandler.open_account()

      {:reply, _deposited} =
        :deposit
        |> TestSupport.command_message(%{"id" => account_id, "amount" => 100})
        |> MessageHandler.deposit()

      log =
        ExUnit.CaptureLog.capture_log(fn ->
          :ok = _explode(account_id)
          :ok = _await_unregistered(account_id)
        end)

      assert log =~ "aggregate exploded"

      {:reply, withdrawn} =
        :withdraw
        |> TestSupport.command_message(%{"id" => account_id, "amount" => 100})
        |> MessageHandler.withdraw()

      assert {:ok, 2} == withdrawn.response
      assert {:ok, _fresh_pid} = _registry_get(account_id)
    end
  end

  describe "aggregate start failure" do
    test "an aggregate that fails to start returns and logs an error and keeps its pid facade" do
      account_id = _id()
      facade_before = _pid_facade(BrokenAggregate)

      {{:reply, replied}, log} =
        ExUnit.CaptureLog.with_log(fn ->
          :open_account
          |> TestSupport.command_message(%{"id" => account_id})
          |> BrokenMessageHandler.open_account()
        end)

      assert {:error, {%RuntimeError{message: "initial state unavailable"}, _stacktrace}} =
               replied.response

      assert log =~
               "[error] Failed to start X3m.System.Test.Account.BrokenAggregate #{inspect(account_id)}"

      assert log =~ "initial state unavailable"

      assert facade_before == _pid_facade(BrokenAggregate)
      assert [] == _aggregate_pids(BrokenAggregate)
      assert :error == _registry_get(BrokenAggregate, account_id)
    end

    test "an aggregate that fails to rehydrate returns and logs an error and keeps its pid facade" do
      account_id = _id()
      :ok = _seed_broken_account(account_id)
      facade_before = _pid_facade(BrokenAggregate)

      {{:reply, replied}, log} =
        ExUnit.CaptureLog.with_log(fn ->
          :deposit
          |> TestSupport.command_message(%{"id" => account_id, "amount" => 100})
          |> BrokenMessageHandler.deposit()
        end)

      assert {:error, {%RuntimeError{message: "initial state unavailable"}, _stacktrace}} =
               replied.response

      assert log =~
               "[error] Failed to start X3m.System.Test.Account.BrokenAggregate #{inspect(account_id)}"

      assert facade_before == _pid_facade(BrokenAggregate)
      assert [] == _aggregate_pids(BrokenAggregate)
      assert :error == _registry_get(BrokenAggregate, account_id)
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

  defp _seed_broken_account(account_id) do
    message = %X3m.System.Message{
      X3m.System.Message.new(:open_account)
      | events: [%Events.Opened{id: account_id, owner_id: "u1"}],
        aggregate_meta: %{id: account_id, version: -1}
    }

    {:ok, 0} = EventStore.save_events("broken-accounts-" <> account_id, message, %{})
    :ok
  end

  defp _unload(account_id) do
    X3m.System.Test.Account.Aggregate
    |> X3m.System.AggregatePidFacade.name()
    |> X3m.System.AggregatePidFacade.exit_process(account_id, :unload_for_test)
  end

  defp _registry_get(aggregate_mod \\ X3m.System.Test.Account.Aggregate, account_id) do
    aggregate_mod
    |> X3m.System.AggregateRegistry.name()
    |> X3m.System.AggregateRegistry.get(account_id)
  end

  defp _await_unregistered(account_id, attempts \\ 100)

  defp _await_unregistered(_account_id, 0),
    do: :still_registered

  defp _await_unregistered(account_id, attempts) do
    account_id
    |> _registry_get()
    |> case do
      :error ->
        :ok

      {:ok, _pid} ->
        Process.sleep(10)
        _await_unregistered(account_id, attempts - 1)
    end
  end

  defp _open_with_slow_saves(account_id) do
    {:reply, _opened} =
      :open_account
      |> TestSupport.command_message(%{"id" => account_id, "owner_id" => "u1"})
      |> TimeoutMessageHandler.open_account()

    # save_events slower than the 50ms commit_timeout
    EventStore.delay("timeout-accounts-" <> account_id, 200)
  end

  defp _time_out_deposit(account_id) do
    try do
      :deposit
      |> TestSupport.command_message(%{"id" => account_id, "amount" => 100})
      |> TimeoutMessageHandler.deposit()
    rescue
      MatchError -> :ok
    catch
      :exit, _reason -> :ok
    end
  end

  defp _explode(account_id) do
    try do
      :explode
      |> TestSupport.command_message(%{"id" => account_id})
      |> MessageHandler.explode()
    catch
      :exit, _reason -> :ok
    end
  end

  # one more teardown than the aggregate supervisor tolerates restarts for, inside its window
  defp _tear_down_past_restart_intensity(tear_down) do
    %DynamicSupervisor{max_restarts: max_restarts, max_seconds: max_seconds} =
      :sys.get_state(_aggregate_sup())

    started_at = System.monotonic_time(:millisecond)
    Enum.each(0..max_restarts, fn _run -> tear_down.() end)
    elapsed_ms = System.monotonic_time(:millisecond) - started_at

    assert elapsed_ms < max_seconds * 1_000,
           "#{max_restarts + 1} teardowns took #{elapsed_ms}ms, outside the #{max_seconds}s restart window"
  end

  defp _pid_facade(aggregate_mod \\ X3m.System.Test.Account.Aggregate) do
    aggregate_mod
    |> X3m.System.AggregatePidFacade.name()
    |> Process.whereis()
  end

  defp _aggregate_sup() do
    X3m.System.Test.Account.Aggregate
    |> X3m.System.AggregateSup.name()
    |> Process.whereis()
  end

  defp _aggregate_pids(aggregate_mod \\ X3m.System.Test.Account.Aggregate) do
    aggregate_mod
    |> X3m.System.AggregateSup.name()
    |> DynamicSupervisor.which_children()
    |> Enum.map(fn {_id, pid, _type, _modules} -> pid end)
    |> Enum.sort()
  end

  defp _id(), do: X3m.System.Uuid.v7()
end
