defmodule X3m.System.Test.Account.EventStore do
  @moduledoc false
  # In-memory event store implementing X3m.System.Aggregate.Repo for tests.
  # Stores %{stream_name => [{event, event_number, metadata}]} (events in order),
  # stamps message.id into each event's metadata (for replay-idempotency), enforces
  # optimistic concurrency on save (expected = message.aggregate_meta.version), and
  # supports per-stream fault/delay injection.
  use X3m.System.Aggregate.Repo
  use Agent

  alias X3m.System.Message

  @spec start_link(opts :: keyword()) :: {:ok, pid :: pid()}
  def start_link(_opts \\ []),
    do: Agent.start_link(fn -> %{streams: %{}, faults: %{}, delays: %{}} end, name: __MODULE__)

  @doc "Resets all streams and injected faults/delays."
  @spec reset() :: :ok
  def reset(),
    do: Agent.update(__MODULE__, fn _state -> %{streams: %{}, faults: %{}, delays: %{}} end)

  @doc "Forces the next save_events/3 on `stream_name` to return `result` (one-shot)."
  @spec fail(stream_name :: String.t(), result :: tuple()) :: :ok
  def fail(stream_name, result),
    do: Agent.update(__MODULE__, &put_in(&1, [:faults, stream_name], result))

  @doc "Makes save_events/3 on `stream_name` sleep `ms` before returning."
  @spec delay(stream_name :: String.t(), ms :: non_neg_integer()) :: :ok
  def delay(stream_name, ms),
    do: Agent.update(__MODULE__, &put_in(&1, [:delays, stream_name], ms))

  @doc "Returns the stored {event, number, metadata} tuples for `stream_name`."
  @spec dump(stream_name :: String.t()) ::
          [{event :: struct(), number :: integer(), metadata :: map()}]
  def dump(stream_name),
    do: Agent.get(__MODULE__, &Map.get(&1.streams, stream_name, []))

  @impl true
  def has?(stream_name),
    do: Agent.get(__MODULE__, &Map.has_key?(&1.streams, stream_name))

  @impl true
  def stream_events(stream_name, _start_at \\ 0, _per_page \\ 1_000),
    do: Agent.get(__MODULE__, &Map.get(&1.streams, stream_name, []))

  @impl true
  def delete_stream(stream_name, _hard_delete?, _expected_version) do
    Agent.update(__MODULE__, &%{&1 | streams: Map.delete(&1.streams, stream_name)})
    :ok
  end

  @impl true
  def save_events(stream_name, %Message{} = message, events_metadata) do
    _maybe_delay(stream_name)

    __MODULE__
    |> Agent.get(&Map.get(&1.faults, stream_name))
    |> case do
      nil ->
        _append(stream_name, message, events_metadata)

      result ->
        Agent.update(__MODULE__, &%{&1 | faults: Map.delete(&1.faults, stream_name)})
        result
    end
  end

  defp _maybe_delay(stream_name) do
    __MODULE__
    |> Agent.get(&Map.get(&1.delays, stream_name))
    |> case do
      nil -> :ok
      ms -> Process.sleep(ms)
    end
  end

  defp _append(stream_name, %Message{} = message, events_metadata) do
    __MODULE__
    |> Agent.get_and_update(fn state ->
      existing = Map.get(state.streams, stream_name, [])
      current_version = length(existing) - 1
      expected_version = message.aggregate_meta.version

      if expected_version != current_version do
        {{:error, :wrong_expected_version, current_version}, state}
      else
        metadata = Map.put(events_metadata, :message_id, message.id)

        appended =
          message.events
          |> Enum.with_index(current_version + 1)
          |> Enum.map(fn {event, number} -> {event, number, metadata} end)

        last_event_number = current_version + length(message.events)
        streams = Map.put(state.streams, stream_name, existing ++ appended)
        {{:ok, last_event_number}, %{state | streams: streams}}
      end
    end)
  end
end
