defmodule X3m.System.GenAggregate do
  use GenServer, restart: :transient

  alias X3m.System.Message
  @behaviour X3m.System.GenAggregateMod

  defmodule State do
    @enforce_keys ~w(aggregate_mod aggregate_state commit_timeout)a
    defstruct @enforce_keys
  end

  def start_link(aggregate_mod, opts \\ []),
    do: GenServer.start_link(__MODULE__, {aggregate_mod, opts}, opts)

  @impl X3m.System.GenAggregateMod
  @spec apply_event_stream(pid, function) :: :ok
  def apply_event_stream(pid, event_stream),
    do: GenServer.call(pid, {:apply_event_stream, event_stream})

  @impl X3m.System.GenAggregateMod
  def handle_msg(pid, cmd, %Message{} = message, opts) do
    commit_timeout = Keyword.fetch!(opts, :commit_timeout)
    GenServer.call(pid, {:handle_msg, cmd, message, commit_timeout}, commit_timeout)
  end

  @impl X3m.System.GenAggregateMod
  @spec commit(pid, String.t(), Message.t(), integer) ::
          {:ok, X3m.System.Aggregate.State.t()} | :transaction_timeout
  def commit(pid, transaction_id, %Message{} = message, last_version) do
    send(pid, {:commit, transaction_id, message, last_version, self()})

    receive do
      {:transaction_commited, ^transaction_id, aggregate_state} -> {:ok, aggregate_state}
    after
      # Commit is applying events only. It should be fast!
      # This timeout is not the same aggregate is waiting to receive :commit message!
      1_000 -> :transaction_timeout
    end
  end

  # Server side

  @impl GenServer
  def init({aggregate_mod, opts}) do
    state = %State{
      aggregate_mod: aggregate_mod,
      aggregate_state: X3m.System.Aggregate.initial_state(aggregate_mod),
      commit_timeout: Keyword.get(opts, :commit_timeout, 5_000)
    }

    {:ok, state}
  end

  @impl GenServer
  def handle_call({:apply_event_stream, event_stream}, _from, %State{} = state) do
    aggregate_state =
      event_stream
      |> Enum.reduce(state.aggregate_state, fn {event, event_number, event_metadata}, acc ->
        apply(state.aggregate_mod, :apply_events, [[event], event_number, event_metadata, acc])
      end)

    {:reply, :ok, %State{state | aggregate_state: aggregate_state}}
  end

  def handle_call(
        {:handle_msg, cmd, %Message{} = message, commit_timeout},
        _from,
        %State{} = state
      ) do
    Logger.metadata(message.logger_metadata)
    # TODO: if version is already sent do optimistic locking
    aggregate_meta = Map.put(message.aggregate_meta, :version, state.aggregate_state.version)
    message = Map.put(message, :aggregate_meta, aggregate_meta)

    state.aggregate_mod
    |> apply(cmd, [message, state.aggregate_state])
    |> case do
      {:block, %Message{} = message, %X3m.System.Aggregate.State{} = aggregate_state} ->
        state = %State{state | aggregate_state: aggregate_state}
        transaction_id = UUID.uuid4()
        response = {:block, message, transaction_id}
        Logger.metadata([])

        {:reply, response, state,
         {:continue, {:wait_for_commit, transaction_id, cmd, commit_timeout}}}

      {:noblock, %Message{} = message, %X3m.System.Aggregate.State{} = aggregate_state} ->
        state = %State{state | aggregate_state: aggregate_state}
        response = {:noblock, message, aggregate_state}
        Logger.metadata([])
        {:reply, response, state}
    end
  end

  @impl GenServer
  def handle_continue({:wait_for_commit, transaction_id, cmd, commit_timeout}, %State{} = state) do
    receive do
      {:commit, ^transaction_id, %Message{} = message, last_version, from} ->
        %X3m.System.Aggregate.State{} =
          aggregate_state =
          apply(state.aggregate_mod, :apply_events, [
            message.events,
            last_version,
            nil,
            state.aggregate_state
          ])

        processed_messages = MapSet.put(aggregate_state.processed_messages, message.id)

        state = %State{
          state
          | aggregate_state: %{aggregate_state | processed_messages: processed_messages}
        }

        response = {:transaction_commited, transaction_id, aggregate_state}
        send(from, response)

        {:noreply, state}
    after
      commit_timeout ->
        X3m.System.Instrumenter.execute(
          :aggregate_commit_timeout,
          %{timeout_after: state.commit_timeout},
          %{aggregate: state.aggregate_mod, message: cmd}
        )

        {:stop, {:commit_timeout, commit_timeout}, state}
    end
  end
end
