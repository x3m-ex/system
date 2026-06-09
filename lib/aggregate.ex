defmodule X3m.System.Aggregate do
  @moduledoc """
  Behaviour and macros for defining an aggregate: the unit that decides how a command
  is handled and how events change its state.

  An aggregate is a plain module that `use`s this one. It declares its starting state
  with `c:initial_state/0`, one `handle_msg/2` (or `handle_msg/3`) clause per command,
  and an `apply_event/2` clause per event:

      defmodule MyApp.Accounts.Aggregate do
        use X3m.System.Aggregate
        alias X3m.System.Message, as: SysMsg

        defmodule State, do: defstruct [:id, balance: 0]

        @impl X3m.System.Aggregate
        def initial_state, do: %State{}

        # validate with Command.new/2, then run Handler.process/2 on success
        handle_msg :open_account, &Command.Open.new/2, &Handler.Open.process/2

        # or a single function that returns {:block | :noblock, message, state}
        handle_msg :deposit, fn %SysMsg{} = msg, %State{} = state ->
          event = %Events.Deposited{id: state.id, amount: msg.request.amount}

          msg =
            msg
            |> SysMsg.add_event(event)
            |> SysMsg.ok()

          {:block, msg, state}
        end

        def apply_event(%Events.Opened{} = e, %State{} = state),
          do: %State{state | id: e.id}

        def apply_event(%Events.Deposited{} = e, %State{} = state),
          do: %State{state | balance: state.balance + e.amount}
      end

  A command handler returns one of:

    * `{:block, message, state}` - there are events to persist; the message handler
      saves them and replies once the commit succeeds.
    * `{:noblock, message, state}` - nothing to persist; the response is returned as-is.

  The macros wrap your functions with idempotency (a message whose id was already
  processed returns `:ok` without re-running) and telemetry. State is rebuilt from the
  event stream by replaying `apply_event/2`, so aggregates are event-sourced by default;
  override `processed_message_id/1`, `commit/2` and `rollback/2` for finer control.

  See the "Aggregates & Event Sourcing" guide for the full flow.
  """

  defmodule State do
    @moduledoc !"""
               Internal. Wraps an aggregate's client state with its version and the set of
               already-processed message ids.
               """
    @type t :: %__MODULE__{version: integer, client_state: any}
    defstruct version: -1, client_state: nil, processed_messages: MapSet.new()
  end

  @doc """
  Returns the aggregate's starting client state (before any events are applied).
  """
  @callback initial_state :: map()

  # Wraps `aggregate_mod`'s `initial_state/0` in the internal `State` struct. Used by
  # the aggregate process when it spawns; not part of the public API.
  @doc false
  @spec initial_state(aggregate_mod :: module()) :: State.t()
  def initial_state(aggregate_mod),
    do: %State{client_state: apply(aggregate_mod, :initial_state, [])}

  @doc """
  Defines a command handler `msg_name/2` from a single `fun`.

  `fun` receives the `X3m.System.Message` and the current client state and must return
  `{:block | :noblock, message, state}`.
  """
  defmacro handle_msg(msg_name, fun) do
    quote do
      @spec unquote(msg_name)(X3m.System.Message.t(), X3m.System.Aggregate.State.t()) ::
              {:block | :noblock, X3m.System.Message.t(), X3m.System.Aggregate.State.t()}
      def unquote(msg_name)(%X3m.System.Message{} = message, %State{} = state) do
        if MapSet.member?(state.processed_messages, message.id) do
          Logger.warning("This message was already processed by aggregate. Returning :ok")
          message = X3m.System.Message.ok(message)
          {:noblock, message, state}
        else
          X3m.System.Instrumenter.execute(:handle_msg, %{}, %{
            aggregate: __MODULE__,
            message: unquote(msg_name)
          })

          client_state = state.client_state || raise("Aggregate state wasn't set")

          {label, %X3m.System.Message{} = message, client_state} =
            unquote(fun).(message, client_state)

          {label, message, %State{state | client_state: client_state}}
          |> _post_processor()
        end
      end
    end
  end

  @doc """
  Defines a command handler `msg_name/2` that first validates, then processes.

  `validate_fun` receives the message and client state. If it returns a halted message
  (e.g. via `X3m.System.Message.put_request/2` on an invalid changeset) processing
  stops and that message is returned. Otherwise `on_success` runs and must return
  `{:block | :noblock, message, state}`.
  """
  defmacro handle_msg(msg_name, validate_fun, on_success) do
    quote do
      @spec unquote(msg_name)(X3m.System.Message.t(), X3m.System.Aggregate.State.t()) ::
              {:block | :noblock, X3m.System.Message.t(), X3m.System.Aggregate.State.t()}
      def unquote(msg_name)(%X3m.System.Message{} = message, %State{} = state) do
        if MapSet.member?(state.processed_messages, message.id) do
          Logger.warning("This message was already processed by aggregate. Returning :ok")
          message = X3m.System.Message.ok(message)
          {:noblock, message, state}
        else
          X3m.System.Instrumenter.execute(:handle_msg, %{}, %{
            aggregate: __MODULE__,
            message: unquote(msg_name)
          })

          client_state = state.client_state || raise("Aggregate state wasn't set")

          case unquote(validate_fun).(message, client_state) do
            %X3m.System.Message{halted?: true} = message ->
              {:noblock, message, state}

            %X3m.System.Message{} = message ->
              {label, %X3m.System.Message{} = message, client_state} =
                unquote(on_success).(message, client_state)

              {label, message, %State{state | client_state: client_state}}
          end
          |> _post_processor()
        end
      end
    end
  end

  defmacro __using__(_opts) do
    quote do
      alias X3m.System.Aggregate
      alias X3m.System.Aggregate.State, as: AggregateState
      require Aggregate
      require Logger
      import Aggregate
      @behaviour Aggregate

      def apply_events(events, last_version, %AggregateState{} = state),
        do: apply_events(events, last_version, nil, state)

      @doc false
      def apply_events([event | tail], last_version, metadata, %AggregateState{} = state) do
        new_client_state = apply_event(event, state.client_state)

        processed_messages =
          if id = apply(__MODULE__, :processed_message_id, [metadata]) do
            MapSet.put(state.processed_messages, id)
          else
            state.processed_messages
          end

        apply_events(tail, last_version, metadata, %AggregateState{
          state
          | processed_messages: processed_messages,
            client_state: new_client_state
        })
      end

      def apply_events([], last_version, _, %AggregateState{} = state),
        do: %AggregateState{state | version: last_version}

      def processed_message_id(nil), do: nil
      @before_compile X3m.System.Aggregate
    end
  end

  defmacro __before_compile__(_env) do
    quote do
      def apply_event(_event, state),
        do: state

      def commit(%X3m.System.Message{}, _client_state),
        do: :ok

      def rollback(%X3m.System.Message{}, _client_state),
        do: :ok

      @spec _post_processor(
              {:block | :noblock, X3m.System.Message.t(), X3m.System.Aggregate.State.t()}
            ) ::
              {:block | :noblock, X3m.System.Message.t(), X3m.System.Aggregate.State.t()}
      def _post_processor(response),
        do: response

      def processed_message_id(_catch_all), do: nil
    end
  end
end
