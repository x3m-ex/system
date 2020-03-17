defmodule X3m.System.Aggregate.Repo do
  @callback has?(stream_name :: String.t()) :: boolean
  @callback stream_events(
              stream_name :: String.t(),
              start_at :: non_neg_integer(),
              per_page :: pos_integer()
            ) :: Enumerable.t()
  @callback delete_stream(
              stream_name :: String.t(),
              hard_delete? :: boolean,
              expected_version :: integer()
            ) :: :ok
  @callback save_events(
              stream_name :: String.t(),
              message :: X3m.System.Message.t(),
              events_metadata :: map()
            ) ::
              {:ok, last_event_number :: integer}
              | {:error, :wrong_expected_version, expected_last_event_number :: integer}
              | {:error, any}

  defmacro __using__(_opts) do
    quote do
      @moduledoc false

      @behaviour X3m.System.Aggregate.Repo
    end
  end
end
