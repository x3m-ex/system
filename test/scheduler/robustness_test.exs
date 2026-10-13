defmodule X3m.System.Scheduler.RobustnessTest do
  use ExUnit.Case, async: false

  alias X3m.System.Message
  alias X3m.System.Test.ProbeScheduler

  describe "loading alarms" do
    test "a failing alarm store leaves the scheduler running and logs a warning" do
      {pid, log} =
        ExUnit.CaptureLog.with_log(fn ->
          pid = _start(load: fn _from, _until -> {:error, :store_down} end)
          assert_receive {:load_alarms, nil, _until, _now}
          assert :ok == _schedule("aggregate_id")
          pid
        end)

      assert pid == Process.whereis(ProbeScheduler)
      assert log =~ "[warning] Loading alarms failed"
      assert log =~ ":store_down"
    end

    test "a store that stays down is retried by the same scheduler on the next tick" do
      pid = _start(load: fn _from, _until -> {:error, :store_down} end, restart: :permanent)
      assert_receive {:load_alarms, nil, _until, _now}

      assert_receive {:load_alarms, nil, _until, _now}, 4 * ProbeScheduler.interval_ms()
      assert pid == Process.whereis(ProbeScheduler)
    end

    test "a failed load is retried for the same window" do
      loads = :counters.new(1, [])

      load = fn _from, _until ->
        :ok = :counters.add(loads, 1, 1)

        case :counters.get(loads, 1) do
          2 -> {:error, :store_down}
          _other -> {:ok, []}
        end
      end

      interval_ms = ProbeScheduler.interval_ms()
      pid = _start(load: load, restart: :permanent)
      assert_receive {:load_alarms, nil, first_until, _now}
      assert_receive {:load_alarms, ^first_until, _failed_until, _now}, 4 * interval_ms
      assert_receive {:load_alarms, retried_from, _until, _now}, 4 * interval_ms

      assert first_until == retried_from
      assert pid == Process.whereis(ProbeScheduler)
    end

    test "an alarm due exactly at the end of the loaded window is delivered" do
      pid = _start(load: _load_once(fn until -> until end))
      assert_receive {:load_alarms, nil, until, _now}
      assert_receive {:loaded, %Message{id: id, assigns: %{dispatch_at: ^until}}}

      assert_receive {:service_responded, %Message{id: ^id}, _dispatcher}, 1_000
      assert pid == Process.whereis(ProbeScheduler)
    end

    test "an alarm due after the loaded window is delivered" do
      pid = _start(load: _load_once(fn until -> DateTime.add(until, 100, :millisecond) end))
      assert_receive {:load_alarms, nil, until, _now}
      assert_receive {:loaded, %Message{id: id, assigns: %{dispatch_at: dispatch_at}}}
      assert :gt == DateTime.compare(dispatch_at, until)

      assert_receive {:service_responded, %Message{id: ^id}, _dispatcher}, 1_000
      assert pid == Process.whereis(ProbeScheduler)
    end

    test "the loaded window stays two intervals ahead of now" do
      _pid = _start([])
      interval_ms = ProbeScheduler.interval_ms()

      lookaheads =
        1..4
        |> Enum.map(fn _tick ->
          assert_receive {:load_alarms, _from, until, now}, interval_ms * 4
          DateTime.diff(until, now, :millisecond)
        end)

      assert Enum.all?(lookaheads, &(abs(&1 - 2 * interval_ms) < div(interval_ms, 2))),
             "lookahead per tick #{inspect(lookaheads)}ms, expected ~#{2 * interval_ms}ms"
    end
  end

  describe "delivering alarms" do
    test "scheduling the same message twice delivers it once" do
      _pid = _start([])
      assert_receive {:load_alarms, nil, _until, _now}
      %Message{id: id} = msg = Message.new(:wrong_service)

      :ok = ProbeScheduler.dispatch(msg, "aggregate_id", in: 10)
      :ok = ProbeScheduler.dispatch(msg, "aggregate_id", in: 10)

      assert_receive {:service_responded, %Message{id: ^id}, _dispatcher}
      refute_receive {:service_responded, %Message{id: ^id}, _dispatcher}, 100
    end

    test "an alarm the store returns again while it is scheduled is delivered once" do
      {:ok, store} = Agent.start_link(fn -> %{} end)

      save = fn %Message{} = msg ->
        Agent.update(store, &Map.put(&1, msg.id, msg))
      end

      load = fn _from, _until -> {:ok, Agent.get(store, &Map.values/1)} end

      respond = fn %Message{} = msg ->
        Agent.update(store, &Map.delete(&1, msg.id))
      end

      interval_ms = ProbeScheduler.interval_ms()
      _pid = _start(save: save, load: load, respond: respond)
      assert_receive {:load_alarms, nil, _until, _now}
      %Message{id: id} = msg = Message.new(:wrong_service)

      :ok = ProbeScheduler.dispatch(msg, "aggregate_id", in: interval_ms + div(interval_ms, 2))
      assert_receive {:load_alarms, _from, _until, _now}, 2 * interval_ms
      assert [%Message{id: ^id}] = Agent.get(store, &Map.values/1)

      assert_receive {:service_responded, %Message{id: ^id}, _dispatcher}, 1_000
      refute_receive {:service_responded, %Message{id: ^id}, _dispatcher}, 2 * interval_ms
    end

    test "a delivered message can be scheduled again" do
      _pid = _start([])
      assert_receive {:load_alarms, nil, _until, _now}
      %Message{id: id} = msg = Message.new(:wrong_service)

      :ok = ProbeScheduler.dispatch(msg, "aggregate_id", in: 10)
      assert_receive {:service_responded, %Message{id: ^id}, dispatcher}
      :ok = _await_down(dispatcher)

      :ok = ProbeScheduler.dispatch(msg, "aggregate_id", in: 10)
      assert_receive {:service_responded, %Message{id: ^id}, _dispatcher}
    end

    test "a raising service_responded leaves the scheduler running and is logged" do
      pid = _start(respond: fn _msg -> raise "service_responded failed" end)
      assert_receive {:load_alarms, nil, _until, _now}

      log =
        ExUnit.CaptureLog.capture_log(fn ->
          :ok = ProbeScheduler.dispatch(Message.new(:wrong_service), "aggregate_id", in: 10)
          assert_receive {:service_responded, %Message{}, dispatcher}
          :ok = _await_down(dispatcher)
        end)

      assert :ok == _schedule("aggregate_id")
      assert pid == Process.whereis(ProbeScheduler)
      assert log =~ "[error] Delivering alarm"
      assert log =~ "service_responded failed"
    end

    test "a save_alarm error is returned by dispatch" do
      pid = _start(save: fn _msg -> {:error, :store_down} end)
      assert_receive {:load_alarms, nil, _until, _now}

      assert {:error, :store_down} == _schedule("aggregate_id")
      assert pid == Process.whereis(ProbeScheduler)
    end

    test "scheduling an already scheduled message does not save it again" do
      test_pid = self()

      save = fn %Message{id: id} ->
        send(test_pid, {:saved, id})
        :ok
      end

      _pid = _start(save: save)
      assert_receive {:load_alarms, nil, _until, _now}
      %Message{id: id} = msg = Message.new(:wrong_service)

      :ok = ProbeScheduler.dispatch(msg, "aggregate_id", in: ProbeScheduler.interval_ms())
      :ok = ProbeScheduler.dispatch(msg, "aggregate_id", in: ProbeScheduler.interval_ms())

      assert_received {:saved, ^id}
      refute_received {:saved, ^id}
    end

    test "a raising save_alarm returns and logs an error and leaves the scheduler running" do
      pid = _start(save: fn _msg -> raise "save_alarm failed" end)
      assert_receive {:load_alarms, nil, _until, _now}

      {result, log} = ExUnit.CaptureLog.with_log(fn -> _schedule("aggregate_id") end)

      assert {:error, %RuntimeError{message: "save_alarm failed"}} = result
      assert pid == Process.whereis(ProbeScheduler)
      assert log =~ "[error] Saving alarm"
      assert log =~ "save_alarm failed"
    end

    test "a raising handler is reported to service_responded and leaves the scheduler running" do
      pid = _start([])
      assert_receive {:load_alarms, nil, _until, _now}
      %Message{id: id} = msg = Message.new(:raising)

      :ok = ProbeScheduler.dispatch(msg, "aggregate_id", in: 10)

      assert_receive {:service_responded, %Message{id: ^id, response: response}, dispatcher},
                     1_000

      :ok = _await_down(dispatcher)

      assert {:error, {:badrpc, {:EXIT, {%RuntimeError{message: "handler failed"}, _stacktrace}}}} =
               response

      assert :ok == _schedule("aggregate_id")
      assert pid == Process.whereis(ProbeScheduler)
    end
  end

  defp _start(opts) do
    {restart, opts} = Keyword.pop(opts, :restart, :temporary)

    overrides = Map.new(opts)

    probe =
      %{
        test_pid: self(),
        save: fn _msg -> :ok end,
        load: fn _from, _until -> {:ok, []} end,
        respond: fn _msg -> :ok end
      }
      |> Map.merge(overrides)

    %{id: ProbeScheduler, start: {ProbeScheduler, :start_link, [probe]}, restart: restart}
    |> start_supervised!()
  end

  # far enough ahead that its dispatch never fires during the test
  defp _schedule(aggregate_id) do
    :wrong_service
    |> Message.new()
    |> ProbeScheduler.dispatch(aggregate_id, in: 3_600_000)
  end

  defp _load_once(dispatch_at_fun) do
    test_pid = self()

    fn
      nil, until ->
        msg =
          :wrong_service
          |> Message.new()
          |> Message.assign(:dispatch_at, dispatch_at_fun.(until))

        send(test_pid, {:loaded, msg})
        {:ok, [msg]}

      _from, _until ->
        {:ok, []}
    end
  end

  defp _await_down(pid) do
    ref = Process.monitor(pid)

    receive do
      {:DOWN, ^ref, :process, ^pid, _reason} -> :ok
    after
      1_000 -> :still_alive
    end
  end
end
