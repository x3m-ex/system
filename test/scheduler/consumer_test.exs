defmodule X3m.System.Scheduler.ConsumerTest do
  use ExUnit.Case, async: false

  alias X3m.System.Message

  test "a scheduler module can use Logger and the injected aliases without its own require" do
    {[{scheduler, _bytecode}], diagnostics} =
      Code.with_diagnostics(fn ->
        Code.compile_string("""
        defmodule X3m.System.Test.LoggingScheduler do
          use X3m.System.Scheduler

          @impl X3m.System.Scheduler
          def save_alarm(%Message{} = msg, _aggregate_id, _test_pid) do
            Logger.info("saving alarm \#{msg.id}")
            :ok
          end

          @impl X3m.System.Scheduler
          def load_alarms(_from, _until, _test_pid), do: {:ok, []}

          @impl X3m.System.Scheduler
          def service_responded(%Message{} = msg, test_pid) do
            send(test_pid, {:responded, msg.id})
            :ok
          end

          def providers(%Message{} = msg), do: Dispatcher.discover_service(msg)

          def loaded_until(%State{loaded_until: loaded_until}), do: loaded_until
        end
        """)
      end)

    assert [] == diagnostics
    start_supervised!({scheduler, self()})
    %Message{id: id} = msg = Message.new(:wrong_service)

    log =
      ExUnit.CaptureLog.capture_log(fn ->
        :ok = scheduler.dispatch(msg, "aggregate_id", in: 10)
        assert_receive {:responded, ^id}, 1_000
      end)

    assert log =~ "saving alarm #{id}"
  end

  test "a scheduler module can add its own handle_call and handle_info clauses" do
    {[{scheduler, _bytecode}], diagnostics} =
      Code.with_diagnostics(fn ->
        Code.compile_string("""
        defmodule X3m.System.Test.ExtendedScheduler do
          use X3m.System.Scheduler

          @impl X3m.System.Scheduler
          def save_alarm(%Message{}, _aggregate_id, _test_pid), do: :ok

          @impl X3m.System.Scheduler
          def load_alarms(_from, _until, _test_pid), do: {:ok, []}

          @impl X3m.System.Scheduler
          def service_responded(%Message{}, _test_pid), do: :ok

          def handle_call(:ping, _from, state), do: {:reply, :pong, state}

          def handle_info({:ping, pid}, state) do
            send(pid, :pong)
            {:noreply, state}
          end
        end
        """)
      end)

    refute Enum.any?(diagnostics, &(&1.severity == :error))
    refute Enum.any?(diagnostics, &(&1.message =~ "cannot match"))
    start_supervised!({scheduler, self()})

    send(scheduler, {:ping, self()})

    assert_receive :pong
    assert :pong == GenServer.call(scheduler, :ping)
  end
end
