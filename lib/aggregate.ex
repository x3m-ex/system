defmodule X3m.System.Aggregate do
  defmodule State do
    @type t :: %__MODULE__{version: integer, client_state: any}
    defstruct version: -1, client_state: nil, processed_messages: MapSet.new()
  end

  @callback initial_state :: map()

  @spec initial_state(atom) :: State.t()
  def initial_state(aggregate_mod),
    do: %State{client_state: apply(aggregate_mod, :initial_state, [])}

  defmacro handle_msg(msg_name, fun) do
    quote do
      @spec unquote(msg_name)(X3m.System.Message.t(), X3m.System.Aggregate.State.t()) ::
              {:block | :noblock, X3m.System.Message.t(), X3m.System.Aggregate.State.t()}
      def unquote(msg_name)(%X3m.System.Message{} = message, state) do
        if MapSet.member?(state.processed_messages, message.id) do
          Logger.warn("This message was already processed by aggregate. Returning :ok")
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

  defmacro handle_msg(msg_name, validate_fun, on_success) do
    quote do
      @spec unquote(msg_name)(X3m.System.Message.t(), X3m.System.Aggregate.State.t()) ::
              {:block | :noblock, X3m.System.Message.t(), X3m.System.Aggregate.State.t()}
      def unquote(msg_name)(%X3m.System.Message{} = message, state) do
        if MapSet.member?(state.processed_messages, message.id) do
          Logger.warn("This message was already processed by aggregate. Returning :ok")
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
          if id = processed_message_id(metadata) do
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
