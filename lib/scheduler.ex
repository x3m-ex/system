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
  """
  @callback save_alarm(
              X3m.System.Message.t(),
              aggregate_id :: String.t(),
              state :: any()
            ) :: :ok | {:ok, X3m.System.Message.t()}

  @doc """
  Load alarms callback is invoked on Scheduler's init with `load_from` as `nil`,
  and after that it is invoked each `in_memory_interval/0` with `load_from`
  set to previous `load_until` value and new `load_until` will be
  `load_from = 2 * in_memory_interval/0`.
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
      """
      @spec dispatch(Message.t(), String.t(), opts :: Keyword.t()) :: :ok
      def dispatch(%Message{} = msg, aggregate_id, in: dispatch_in_ms) do
        dispatch_at = DateTime.add(_now(), dispatch_in_ms, :millisecond)

        GenServer.call(
          @name,
          {:schedule_dispatch, msg, aggregate_id, dispatch_at, dispatch_in_ms}
        )
      end

      def dispatch(%Message{} = msg, aggregate_id, at: %DateTime{} = dispatch_at) do
        dispatch_in_ms = DateTime.diff(dispatch_at, _now(), :millisecond)

        GenServer.call(
          @name,
          {:schedule_dispatch, msg, aggregate_id, dispatch_at, dispatch_in_ms}
        )
      end

      @spec _now() :: DateTime.t()
      defp _now() do
        {:ok, time} = DateTime.now("Etc/UTC", Tzdata.TimeZoneDatabase)
        time
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
            {:schedule_dispatch, %Message{} = msg, aggregate_id, dispatch_at, dispatch_in_ms},
            _from,
            %State{} = state
          ) do
        msg =
          msg
          |> Message.assign(:dispatch_at, dispatch_at)
          |> Message.assign(:dispatch_attempts, 0)

        msg =
          msg
          |> save_alarm(aggregate_id, state.client_state)
          |> case do
            :ok -> msg
            {:ok, %Message{} = new_message} -> new_message
          end

        scheduled_alarms =
          cond do
            dispatch_in_ms < 0 ->
              msg = Message.assign(msg, :late?, true)
              send(self(), {:dispatch, msg})
              Map.put(state.scheduled_alarms, msg.id, msg)

            DateTime.compare(state.loaded_until, dispatch_at) == :gt ->
              Process.send_after(self(), {:dispatch, msg}, dispatch_in_ms)
              Map.put(state.scheduled_alarms, msg.id, msg)

            true ->
              state.scheduled_alarms
          end

        {:reply, :ok, %State{state | scheduled_alarms: scheduled_alarms}}
      end

      @impl GenServer
      @doc false
      def handle_info(:load_alarms, %State{} = state) do
        load_until =
          (state.loaded_until || DateTime.utc_now())
          |> DateTime.add(in_memory_interval() * 2, :millisecond)

        {:ok, alarms} = load_alarms(state.loaded_until, load_until, state.client_state)

        scheduled_alarms =
          alarms
          |> Enum.reduce(%{}, fn %Message{} = msg, acc ->
            dispatch_in_ms = DateTime.diff(msg.assigns.dispatch_at, _now(), :millisecond)

            cond do
              dispatch_in_ms < 0 ->
                msg = Message.assign(msg, :late?, true)
                send(self(), {:dispatch, msg})
                Map.put_new(acc, msg.id, msg)

              DateTime.compare(load_until, msg.assigns.dispatch_at) == :gt ->
                Process.send_after(@name, {:dispatch, msg}, dispatch_in_ms)
                Map.put_new(acc, msg.id, msg)

              true ->
                :ok
                acc.scheduled_alarms
            end
          end)

        Process.send_after(self(), :load_alarms, in_memory_interval())
        {:noreply, %State{state | loaded_until: load_until, scheduled_alarms: scheduled_alarms}}
      end

      def handle_info({:dispatch, msg}, %State{} = state) do
        spawn_link(fn ->
          timeout = dispatch_timeout(msg)
          msg = %{msg | reply_to: self()}

          attempts = msg.assigns[:dispatch_attempts] || 0

          msg
          |> Message.assign(:dispatch_attempts, attempts + 1)
          |> Dispatcher.dispatch(timeout: timeout)
          |> service_responded(state.client_state)
          |> case do
            :ok ->
              {_, scheduled_alarms} = Map.pop(state.scheduled_alarms, msg.id)
              {:noreply, %State{state | scheduled_alarms: scheduled_alarms}}

            {:retry, in_ms, %Message{} = msg} ->
              msg = _retry_message(msg)
              Process.send_after(@name, {:dispatch, msg}, in_ms)

              scheduled_alarms = Map.put(state.scheduled_alarms, msg.id, msg)
              {:noreply, %State{state | scheduled_alarms: scheduled_alarms}}
          end
        end)

        {:noreply, state}
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
