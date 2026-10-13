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

      alias X3m.System.{Scheduler, Message}

      # kept for the using module's own code, as the runtime that used them moved to Scheduler.Server
      alias X3m.System.Dispatcher, warn: false
      alias X3m.System.Scheduler.State, warn: false
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
      def dispatch(%Message{} = msg, aggregate_id, opts),
        do: X3m.System.Scheduler.Server.dispatch(@name, msg, aggregate_id, opts)

      @impl GenServer
      @doc false
      def init(client_state),
        do: X3m.System.Scheduler.Server.init(client_state)

      # matching only the scheduler's own requests leaves room for the using module's clauses
      @impl GenServer
      @doc false
      def handle_call(
            {:schedule_dispatch, _msg, _aggregate_id, _dispatch_at, _dispatch_in_ms} = request,
            from,
            state
          ),
          do: X3m.System.Scheduler.Server.handle_call(__MODULE__, request, from, state)

      @impl GenServer
      @doc false
      def handle_info(:load_alarms, state),
        do: X3m.System.Scheduler.Server.handle_info(__MODULE__, :load_alarms, state)

      def handle_info({:dispatch, %Message{}} = msg, state),
        do: X3m.System.Scheduler.Server.handle_info(__MODULE__, msg, state)

      def handle_info({:delivered, %Message{}, _result} = msg, state),
        do: X3m.System.Scheduler.Server.handle_info(__MODULE__, msg, state)

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
