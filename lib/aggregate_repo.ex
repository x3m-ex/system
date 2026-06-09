defmodule X3m.System.Aggregate.Repo do
  @moduledoc """
  Behaviour for the event store that backs aggregates.

  An `X3m.System.MessageHandler` reads an aggregate's history and persists its new
  events through a module implementing this behaviour, passed as the `:aggregate_repo`
  option. The library does not ship a concrete store — you implement these four
  callbacks against whatever you use (EventStoreDB/Extreme, Postgres, an in-memory
  store for tests, ...):

      defmodule MyApp.AggregateRepo do
        use X3m.System.Aggregate.Repo

        @impl true
        def has?(stream_name), do: ...

        @impl true
        def stream_events(stream_name, start_at, per_page), do: ...

        @impl true
        def delete_stream(stream_name, hard_delete?, expected_version), do: ...

        @impl true
        def save_events(stream_name, message, events_metadata), do: ...
      end

  Stream names are built by the message handler from its `:stream` option and the
  aggregate id (`"\#{stream}-\#{id}"`).
  """

  @doc """
  Returns whether a stream named `stream_name` exists (i.e. the aggregate has any
  persisted events).
  """
  @callback has?(stream_name :: String.t()) :: boolean

  @doc """
  Returns an enumerable of `{event, event_number, metadata}` tuples for `stream_name`,
  starting at `start_at` and read in pages of `per_page`. Replayed to rebuild state.
  """
  @callback stream_events(
              stream_name :: String.t(),
              start_at :: non_neg_integer(),
              per_page :: pos_integer()
            ) :: Enumerable.t()

  @doc """
  Deletes `stream_name`. `hard_delete?` chooses a hard vs soft delete; `expected_version`
  enables optimistic-concurrency checks (`-2` to skip).
  """
  @callback delete_stream(
              stream_name :: String.t(),
              hard_delete? :: boolean,
              expected_version :: integer()
            ) :: :ok

  @doc """
  Appends `message.events` to `stream_name`, storing `events_metadata` alongside each
  event.

  Returns `{:ok, last_event_number}` with the stream's new version on success. Return
  `{:error, :wrong_expected_version, expected_last_event_number}` on a concurrency
  conflict, or `{:error, reason}` for any other failure (the aggregate process is then
  terminated and the error returned to the caller).
  """
  @callback save_events(
              stream_name :: String.t(),
              message :: X3m.System.Message.t(),
              events_metadata :: map()
            ) ::
              {:ok, last_event_number :: integer}
              | {:error, :wrong_expected_version, expected_last_event_number :: integer}
              | {:error, reason :: any}

  defmacro __using__(_opts) do
    quote do
      @moduledoc false

      @behaviour X3m.System.Aggregate.Repo
    end
  end
end
