defmodule X3m.System.Scheduler do
  @moduledoc """
  This behaviour should be used to schedule `X3m.System.Message` delivery
  at some point in time in the future. Implementation module should persist alarms so when process
  is respawned they can be reloaded into memory.

  Not all scheduled alarms are kept in memory. They are loaded in bulks
  each `in_memory_interval/0` milliseconds for next `2 * in_memory_interval/0` milliseconds.

  If message with its `X3m.System.Message.id` is already in memory (and scheduled for delivery)
  it is ignored.


  When message is processed, `service_responded/2` callback is invoked. It should return either
  `:ok` or `{:retry, in_milliseconds, X3m.System.Message}` if returned message should be redelivered
  in specified number of milliseconds.
  """

  @doc """
  This callback is invoked when `X3m.System.Message` should be saved as an alarm.
  Time when it should be dispatched is set in its `assigns.dispatch_at` as `DateTime`.

  3rd parameter (state) is the one that was set when Scheduler's `start_link/1` was
  called.

  If `{:ok, X3m.System.Message.t()}` is returned, than that message will be dispatched instead
  of original one. This can be used to inject something in message assigns during `save_alarm`.

  If `{:error, reason}` is returned, the alarm is not scheduled and `dispatch/3` returns that
  error. If it raises, the error is logged and `dispatch/3` returns `{:error, exception}`.
  """
  @callback save_alarm(
              X3m.System.Message.t(),
              aggregate_id :: String.t(),
              state :: any()
            ) :: :ok | {:ok, X3m.System.Message.t()} | {:error, reason :: term()}

  @doc """
  Load alarms callback is invoked on Scheduler's init with `load_from` as `nil`,
  and after that it is invoked each `in_memory_interval/0` with `load_from`
  set to the previous successful `load_until` and `load_until` set to
  `2 * in_memory_interval/0` from now.

  Every returned alarm is armed, also one due at or after `load_until`. If `{:error, reason}`
  is returned, a warning is logged and the same `load_from` is retried on the next tick.
  """
  @callback load_alarms(
              load_from :: nil | DateTime.t(),
              load_until :: DateTime.t(),
              state :: any()
            ) ::
              {:ok, [X3m.System.Message.t()]}
              | {:error, term()}

  @doc """
  This callback is invoked when scheduled message is processed.

  It should return either `:ok` (and remove from persitance) so message delivery is not retried or
  amount of milliseconds in which delivery will be retried with potentially
  modifed `X3m.System.Message`. Its `assigns` can used to track number of retries for example.

  It runs outside the Scheduler process: if it raises, the failure is logged and the alarm is
  dropped from memory. It stays in your store, and is only reloaded after a Scheduler restart.
  """
  @callback service_responded(X3m.System.Message.t(), state :: any()) ::
              :ok
              | {:retry, in_ms :: non_neg_integer(), X3m.System.Message.t()}

  @doc """
  This is optional callback that should return in which interval (in milliseconds)
  alarms should be loaded.
  """
  @callback in_memory_interval() :: milliseconds :: pos_integer()

  @doc """
  This optional callback defines timeout for response (in milliseconds). By default
  response is being waited for 5_000 milliseconds
  """
  @callback dispatch_timeout(X3m.System.Message.t()) :: milliseconds :: pos_integer()

  @optional_callbacks in_memory_interval: 0, dispatch_timeout: 1

  defmodule State do
    @moduledoc !"Internal. State of a `X3m.System.Scheduler` GenServer."
    @type t() :: %__MODULE__{
            client_state: any(),
            loaded_until: nil | DateTime.t(),
            scheduled_alarms: %{String.t() => X3m.System.Message.t()}
          }

    @enforce_keys ~w(client_state loaded_until scheduled_alarms)a
    defstruct @enforce_keys
  end

  defmacro __using__(_opts) do
    quote do
      @moduledoc """
      This module should be used to schedule `X3m.System.Message` delivery
      at some point in time in the future. Alarms are persisted so when process
      is respawned they can be reloaded into memory.

      Not all scheduled alarms are kept in memory. They are loaded in bulks
      each `in_memory_interval/0` milliseconds for next `2 * in_memory_interval/0` milliseconds.

      If message with its `X3m.System.Message.id` is already in memory (and scheduled for delivery)
      it is ignored.

      When message is processed, `service_responded/2` callback is invoked. It should return either
      `:ok` or `{:retry, in_milliseconds, X3m.System.Message}` if returned message should be redelivered
      in specified number of milliseconds.
      """
      use GenServer
      require Logger

      alias X3m.System.{Scheduler, Dispatcher, Message}
      alias X3m.System.Scheduler.State
      @behaviour Scheduler

      @name __MODULE__

      @doc """
      Spawns Scheduler with given `state`. That one is provided in all
      callbacks as last parameter and can be used to provide Repo or any other detail needed.

      When new Scheduler is spawned it calls `load_alarms/3` callback with
      `load_from` set to `nil`.
      """
      @spec start_link(state :: any()) :: GenServer.on_start()
      def start_link(state \\ %{}),
        do: GenServer.start_link(__MODULE__, state, name: @name)

      @doc """
      Schedules dispatch of `msg` `in` given milliseconds or `at` given `DateTime`.
      It assigns `:dispatch_at` to the `msg` and that's the real `DateTime` when dispatch 
      should occur.

      opts can be either:
      - `in` - in milliseconds
      - `at` - as `DateTime`

      Returns `save_alarm/3`'s `{:error, reason}`, or `{:error, exception}` if it raises.
      """
      @spec dispatch(Message.t(), aggregate_id :: String.t(), opts :: Keyword.t()) ::
              :ok | {:error, reason :: term()}
      def dispatch(%Message{} = msg, aggregate_id, in: dispatch_in_ms) do
        dispatch_at =
          DateTime.utc_now()
          |> DateTime.add(dispatch_in_ms, :millisecond)

        GenServer.call(
          @name,
          {:schedule_dispatch, msg, aggregate_id, dispatch_at, dispatch_in_ms}
        )
      end

      def dispatch(%Message{} = msg, aggregate_id, at: %DateTime{} = dispatch_at) do
        dispatch_in_ms =
          dispatch_at
          |> DateTime.diff(DateTime.utc_now(), :millisecond)

        GenServer.call(
          @name,
          {:schedule_dispatch, msg, aggregate_id, dispatch_at, dispatch_in_ms}
        )
      end

      @impl GenServer
      @doc false
      def init(client_state) do
        send(self(), :load_alarms)

        {:ok, %State{client_state: client_state, loaded_until: nil, scheduled_alarms: %{}}}
      end

      @impl GenServer
      @doc false
      def handle_call(
            {:schedule_dispatch, %Message{id: id}, _aggregate_id, _dispatch_at, _dispatch_in_ms},
            _from,
            %State{scheduled_alarms: scheduled_alarms} = state
          )
          when is_map_key(scheduled_alarms, id),
          do: {:reply, :ok, state}

      def handle_call(
            {:schedule_dispatch, %Message{} = msg, aggregate_id, dispatch_at, dispatch_in_ms},
            _from,
            %State{} = state
          ) do
        msg
        |> Message.assign(:dispatch_at, dispatch_at)
        |> Message.assign(:dispatch_attempts, 0)
        |> _save_alarm(aggregate_id, state.client_state)
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

      @impl GenServer
      @doc false
      def handle_info(:load_alarms, %State{} = state) do
        load_until =
          DateTime.utc_now()
          |> DateTime.add(in_memory_interval() * 2, :millisecond)

        Process.send_after(self(), :load_alarms, in_memory_interval())

        # dispatched via apply/3 so a load_alarms/3 that never errors keeps the error clause legal
        __MODULE__
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
              "Loading alarms failed, retrying in #{in_memory_interval()}ms: #{inspect(reason)}"
            end)

            {:noreply, state}
        end
      end

      def handle_info({:dispatch, %Message{} = msg}, %State{} = state) do
        scheduler = self()
        client_state = state.client_state

        spawn(fn ->
          result = _deliver(msg, client_state)
          send(scheduler, {:delivered, msg, result})
        end)

        {:noreply, state}
      end

      def handle_info(
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

      def handle_info({:delivered, %Message{} = msg, _done_or_failed}, %State{} = state) do
        scheduled_alarms = Map.delete(state.scheduled_alarms, msg.id)
        {:noreply, %State{state | scheduled_alarms: scheduled_alarms}}
      end

      @spec _save_alarm(Message.t(), aggregate_id :: String.t(), client_state :: any()) ::
              {:ok, Message.t()} | {:error, reason :: term()}
      defp _save_alarm(%Message{} = msg, aggregate_id, client_state) do
        __MODULE__
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

      @spec _loaded?(loaded_until :: nil | DateTime.t(), dispatch_at :: DateTime.t()) ::
              boolean()
      defp _loaded?(nil, _dispatch_at), do: false

      defp _loaded?(%DateTime{} = loaded_until, dispatch_at),
        do: DateTime.compare(loaded_until, dispatch_at) == :gt

      @spec _dispatch_in_ms(Message.t()) :: integer()
      defp _dispatch_in_ms(%Message{} = msg) do
        msg.assigns.dispatch_at
        |> DateTime.diff(DateTime.utc_now(), :millisecond)
      end

      # runs outside the scheduler, so a raising service_responded/2 cannot take it down
      @spec _deliver(Message.t(), client_state :: any()) ::
              :ok | {:retry, in_ms :: non_neg_integer(), Message.t()} | :failed
      defp _deliver(%Message{} = msg, client_state) do
        timeout = dispatch_timeout(msg)
        attempts = msg.assigns[:dispatch_attempts] || 0

        msg
        |> Message.assign(:dispatch_attempts, attempts + 1)
        |> Dispatcher.dispatch(timeout: timeout)
        |> service_responded(client_state)
      catch
        kind, reason ->
          Logger.error(fn ->
            "Delivering alarm #{msg.id} failed: " <>
              Exception.format(kind, reason, __STACKTRACE__)
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

      @doc false
      @spec in_memory_interval() :: milliseconds :: pos_integer()
      def in_memory_interval,
        do: 6 * 60 * 60 * 1_000

      @doc false
      @spec dispatch_timeout(Message.t()) :: milliseconds :: pos_integer()
      def dispatch_timeout(%Message{}),
        do: 5_000

      defoverridable in_memory_interval: 0, dispatch_timeout: 1
    end
  end
end
