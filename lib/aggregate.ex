defmodule X3m.System.Aggregate do
  defmodule State do
    @type t :: %__MODULE__{version: integer, client_state: any}
    defstruct version: -1, client_state: nil
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
        X3m.System.Instrumenter.execute(:handle_msg, %{}, %{
          aggregate: __MODULE__,
          message: unquote(msg_name)
        })

        client_state = state.client_state || raise("Aggregate state wasn't set")

        {label, %X3m.System.Message{} = message, client_state} =
          unquote(fun).(message, client_state)

        {label, message, %State{state | client_state: client_state}}
      end
    end
  end

  defmacro handle_msg(msg_name, validate_fun, on_success) do
    quote do
      @spec unquote(msg_name)(X3m.System.Message.t(), X3m.System.Aggregate.State.t()) ::
              {:block | :noblock, X3m.System.Message.t(), X3m.System.Aggregate.State.t()}
      def unquote(msg_name)(%X3m.System.Message{} = message, state) do
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
      end
    end
  end

  defmacro __using__(_opts) do
    quote do
      alias X3m.System.Aggregate
      alias X3m.System.Aggregate.State, as: AggregateState
      require Aggregate
      import Aggregate
      @behaviour Aggregate

      @doc false
      def apply_events([event | tail], last_version, %AggregateState{} = state) do
        new_client_state = apply_event(event, state.client_state)
        apply_events(tail, last_version, %AggregateState{state | client_state: new_client_state})
      end

      def apply_events([], last_version, %AggregateState{} = state),
        do: %AggregateState{state | version: last_version}

      @before_compile X3m.System.Aggregate
    end
  end

  defmacro __before_compile__(_env) do
    quote do
      def apply_event(_event, state),
        do: state
    end
  end
end
