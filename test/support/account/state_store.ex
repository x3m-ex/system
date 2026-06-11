defmodule X3m.System.Test.Account.StateStore do
  @moduledoc false
  # SQL-like in-memory store of a saved row per aggregate id (non-ES). The stored value is
  # opaque (e.g. the {client_state, version} pair the snapshot handler persists).
  use Agent

  @spec start_link(opts :: keyword()) :: {:ok, pid :: pid()}
  def start_link(_opts \\ []),
    do: Agent.start_link(fn -> %{} end, name: __MODULE__)

  @doc "Clears all stored rows."
  @spec reset() :: :ok
  def reset(),
    do: Agent.update(__MODULE__, fn _state -> %{} end)

  @doc "Upserts the `value` row under `id`."
  @spec put(id :: String.t(), value :: term()) :: :ok
  def put(id, value),
    do: Agent.update(__MODULE__, &Map.put(&1, id, value))

  @doc "Loads the row for `id`, or `:not_found`."
  @spec get(id :: String.t()) :: {:ok, value :: term()} | :not_found
  def get(id) do
    __MODULE__
    |> Agent.get(&Map.fetch(&1, id))
    |> case do
      {:ok, value} -> {:ok, value}
      :error -> :not_found
    end
  end
end
