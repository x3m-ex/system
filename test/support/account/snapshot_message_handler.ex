defmodule X3m.System.Test.Account.SnapshotMessageHandler do
  @moduledoc false
  use X3m.System.MessageHandler,
    aggregate_mod: X3m.System.Test.Account.Aggregate,
    aggregate_repo: X3m.System.Test.Account.EventStore,
    stream: "snapshot-accounts",
    pid_facade_mod: X3m.System.AggregatePidFacade,
    event_metadata: %{app_version: "test"}

  alias X3m.System.Aggregate.State, as: AggregateState
  alias X3m.System.GenAggregate
  alias X3m.System.Message
  alias X3m.System.Test.Account.StateStore

  on_new_aggregate :open_account
  on_aggregate :deposit

  # State-based (non-ES): events are not persisted to an event store; the version simply
  # advances by the number of produced events (what an event store would have returned).
  def save_events(%Message{events: events, aggregate_meta: %{version: version}}),
    do: {:ok, version + length(events)}

  # Persist the FULL state (client_state + version) after commit.
  def save_state(id, %AggregateState{version: version, client_state: client_state}, %Message{}) do
    StateStore.put(id, {client_state, version})
    :ok
  end

  # Hydrate a fresh process from the saved state (no replay): the aggregate's `set_state/1`
  # callback rebuilds client_state and the framework restores the version.
  def when_pid_is_not_registered(_aggregate_mod, id, spawn_new_fun) do
    id
    |> StateStore.get()
    |> case do
      {:ok, {client_state, version}} ->
        {:ok, pid} = spawn_new_fun.()
        :ok = GenAggregate.set_state(pid, client_state, version)
        {:ok, pid}

      :not_found ->
        {:error, :not_found}
    end
  end
end
