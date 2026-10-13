defmodule X3m.System.Scheduler.Server do
  @moduledoc !"""
             Internal. Runtime of a `use X3m.System.Scheduler` module: its generated client
             function and GenServer callbacks delegate here, passing the using module as
             `scheduler` so its callbacks (`save_alarm/3`, `load_alarms/3`, ...) are called
             back on it.

             Kept out of the `__using__` quote so the runtime compiles once, here, where
             coverage can see it, instead of into every using module.
             """

  require Logger

  alias X3m.System.{Dispatcher, Message}
  alias X3m.System.Scheduler.State

  @doc "Schedules `msg` on the `scheduler` process, `in` milliseconds or `at` a `DateTime`."
  @spec dispatch(
          scheduler :: module(),
          Message.t(),
          aggregate_id :: String.t(),
          opts :: Keyword.t()
        ) :: :ok | {:error, reason :: term()}
  def dispatch(scheduler, %Message{} = msg, aggregate_id, in: dispatch_in_ms) do
    dispatch_at =
      DateTime.utc_now()
      |> DateTime.add(dispatch_in_ms, :millisecond)

    GenServer.call(
      scheduler,
      {:schedule_dispatch, msg, aggregate_id, dispatch_at, dispatch_in_ms}
    )
  end

  def dispatch(scheduler, %Message{} = msg, aggregate_id, at: %DateTime{} = dispatch_at) do
    dispatch_in_ms =
      dispatch_at
      |> DateTime.diff(DateTime.utc_now(), :millisecond)

    GenServer.call(
      scheduler,
      {:schedule_dispatch, msg, aggregate_id, dispatch_at, dispatch_in_ms}
    )
  end

  @doc "GenServer `init/1` of a scheduler: loads alarms right after start."
  @spec init(client_state :: any()) :: {:ok, State.t()}
  def init(client_state) do
    send(self(), :load_alarms)

    {:ok, %State{client_state: client_state, loaded_until: nil, scheduled_alarms: %{}}}
  end

  @doc "GenServer `handle_call/3` of `scheduler`."
  @spec handle_call(
          scheduler :: module(),
          request :: term(),
          from :: GenServer.from(),
          State.t()
        ) :: {:reply, reply :: :ok | {:error, reason :: term()}, State.t()}
  def handle_call(
        _scheduler,
        {:schedule_dispatch, %Message{id: id}, _aggregate_id, _dispatch_at, _dispatch_in_ms},
        _from,
        %State{scheduled_alarms: scheduled_alarms} = state
      )
      when is_map_key(scheduled_alarms, id),
      do: {:reply, :ok, state}

  def handle_call(
        scheduler,
        {:schedule_dispatch, %Message{} = msg, aggregate_id, dispatch_at, dispatch_in_ms},
        _from,
        %State{} = state
      ) do
    msg
    |> Message.assign(:dispatch_at, dispatch_at)
    |> Message.assign(:dispatch_attempts, 0)
    |> _save_alarm(scheduler, aggregate_id, state.client_state)
    |> case do
      {:ok, %Message{} = msg} ->
        state =
          cond do
            dispatch_in_ms < 0 -> _arm(state, msg, dispatch_in_ms)
            _loaded?(state.loaded_until, dispatch_at) -> _arm(state, msg, dispatch_in_ms)
            true -> state
          end

        {:reply, :ok, state}

      {:error, _reason} = error ->
        {:reply, error, state}
    end
  end

  @doc "GenServer `handle_info/2` of `scheduler`."
  @spec handle_info(scheduler :: module(), msg :: term(), State.t()) :: {:noreply, State.t()}
  def handle_info(scheduler, :load_alarms, %State{} = state) do
    interval = apply(scheduler, :in_memory_interval, [])

    load_until =
      DateTime.utc_now()
      |> DateTime.add(interval * 2, :millisecond)

    Process.send_after(self(), :load_alarms, interval)

    scheduler
    |> apply(:load_alarms, [state.loaded_until, load_until, state.client_state])
    |> case do
      {:ok, alarms} ->
        %State{} =
          state =
          alarms
          |> Enum.reduce(state, fn %Message{} = msg, acc ->
            _arm(acc, msg, _dispatch_in_ms(msg))
          end)

        {:noreply, %State{state | loaded_until: load_until}}

      {:error, reason} ->
        Logger.warning(fn ->
          "Loading alarms failed, retrying in #{interval}ms: #{inspect(reason)}"
        end)

        {:noreply, state}
    end
  end

  def handle_info(scheduler, {:dispatch, %Message{} = msg}, %State{} = state) do
    server = self()
    client_state = state.client_state

    spawn(fn ->
      result = _deliver(scheduler, msg, client_state)
      send(server, {:delivered, msg, result})
    end)

    {:noreply, state}
  end

  def handle_info(
        _scheduler,
        {:delivered, %Message{} = msg, {:retry, in_ms, %Message{} = retried}},
        %State{} = state
      ) do
    retried = _retry_message(retried)
    Process.send_after(self(), {:dispatch, retried}, in_ms)

    scheduled_alarms =
      state.scheduled_alarms
      |> Map.delete(msg.id)
      |> Map.put(retried.id, retried)

    {:noreply, %State{state | scheduled_alarms: scheduled_alarms}}
  end

  def handle_info(_scheduler, {:delivered, %Message{} = msg, _done_or_failed}, %State{} = state) do
    scheduled_alarms = Map.delete(state.scheduled_alarms, msg.id)
    {:noreply, %State{state | scheduled_alarms: scheduled_alarms}}
  end

  @spec _save_alarm(
          Message.t(),
          scheduler :: module(),
          aggregate_id :: String.t(),
          client_state :: any()
        ) :: {:ok, Message.t()} | {:error, reason :: term()}
  defp _save_alarm(%Message{} = msg, scheduler, aggregate_id, client_state) do
    scheduler
    |> apply(:save_alarm, [msg, aggregate_id, client_state])
    |> case do
      :ok -> {:ok, msg}
      {:ok, %Message{} = new_message} -> {:ok, new_message}
      {:error, _reason} = error -> error
    end
  rescue
    exception ->
      Logger.error(fn ->
        "Saving alarm #{msg.id} failed: " <>
          Exception.format(:error, exception, __STACKTRACE__)
      end)

      {:error, exception}
  end

  # an alarm already in memory is armed once, however often it is scheduled or loaded
  @spec _arm(State.t(), Message.t(), dispatch_in_ms :: integer()) :: State.t()
  defp _arm(%State{scheduled_alarms: scheduled_alarms} = state, %Message{id: id}, _in_ms)
       when is_map_key(scheduled_alarms, id),
       do: state

  defp _arm(%State{} = state, %Message{} = msg, dispatch_in_ms) when dispatch_in_ms < 0 do
    msg = Message.assign(msg, :late?, true)
    send(self(), {:dispatch, msg})
    %State{state | scheduled_alarms: Map.put(state.scheduled_alarms, msg.id, msg)}
  end

  defp _arm(%State{} = state, %Message{} = msg, dispatch_in_ms) do
    Process.send_after(self(), {:dispatch, msg}, dispatch_in_ms)
    %State{state | scheduled_alarms: Map.put(state.scheduled_alarms, msg.id, msg)}
  end

  @spec _loaded?(loaded_until :: nil | DateTime.t(), dispatch_at :: DateTime.t()) :: boolean()
  defp _loaded?(nil, _dispatch_at), do: false

  defp _loaded?(%DateTime{} = loaded_until, dispatch_at),
    do: DateTime.compare(loaded_until, dispatch_at) == :gt

  @spec _dispatch_in_ms(Message.t()) :: integer()
  defp _dispatch_in_ms(%Message{} = msg) do
    msg.assigns.dispatch_at
    |> DateTime.diff(DateTime.utc_now(), :millisecond)
  end

  # runs outside the scheduler, so a raising service_responded/2 cannot take it down
  @spec _deliver(scheduler :: module(), Message.t(), client_state :: any()) ::
          :ok | {:retry, in_ms :: non_neg_integer(), Message.t()} | :failed
  defp _deliver(scheduler, %Message{} = msg, client_state) do
    timeout = apply(scheduler, :dispatch_timeout, [msg])
    attempts = msg.assigns[:dispatch_attempts] || 0

    resolved =
      msg
      |> Message.assign(:dispatch_attempts, attempts + 1)
      |> Dispatcher.dispatch(timeout: timeout)

    apply(scheduler, :service_responded, [resolved, client_state])
  catch
    kind, reason ->
      Logger.error(fn ->
        "Delivering alarm #{msg.id} failed: " <> Exception.format(kind, reason, __STACKTRACE__)
      end)

      :failed
  end

  @spec _retry_message(Message.t()) :: Message.t()
  defp _retry_message(%Message{} = msg) do
    %{
      msg
      | request: nil,
        valid?: true,
        response: nil,
        events: [],
        halted?: false
    }
  end
end
