defmodule Banking.EventStore.AggregateRepo do
  @moduledoc !"""
             Macro providing EventStore operations for aggregate repositories.

             Consumer apps use this macro with their Extreme connection module:

                 use Banking.EventStore.AggregateRepo, extreme: Banking.Core.EventStore
             """

  defmodule Query do
    @moduledoc !"""
               Builds Extreme protocol buffer messages for EventStore operations.
               """
    alias Extreme.Messages, as: ExMsg
    alias X3m.System.Message, as: SysMsg

    @spec write_events(stream :: String.t(), message :: SysMsg.t(), write_metadata :: map()) ::
            ExMsg.WriteEvents.t()
    def write_events(stream, %SysMsg{} = message, write_metadata) do
      emitted_at =
        DateTime.utc_now()
        |> DateTime.to_iso8601()

      metadata = fn ->
        %{
          "$correlationId": message.correlation_id,
          "$causationId": message.id,
          emitted_at: emitted_at
        }
        |> Map.merge(write_metadata)
      end

      proto_events =
        Enum.map(message.events, fn event ->
          ExMsg.NewEvent.new(
            event_id: Extreme.Tools.generate_uuid(),
            event_type: to_string(event.__struct__),
            data_content_type: 1,
            metadata_content_type: 1,
            data: Jason.encode!(Map.from_struct(event)),
            metadata: Jason.encode!(metadata.())
          )
        end)

      ExMsg.WriteEvents.new(
        event_stream_id: stream,
        expected_version: message.aggregate_meta.version,
        events: proto_events,
        require_master: false
      )
    end

    @spec read_events(
            stream :: String.t(),
            start_at :: non_neg_integer(),
            per_page :: pos_integer()
          ) ::
            ExMsg.ReadStreamEvents.t()
    def read_events(stream, start_at, per_page) do
      ExMsg.ReadStreamEvents.new(
        event_stream_id: stream,
        from_event_number: start_at,
        max_count: per_page,
        resolve_link_tos: true,
        require_master: false
      )
    end

    @spec delete_stream(
            stream :: String.t(),
            hard_delete? :: boolean(),
            expected_version :: integer()
          ) ::
            ExMsg.DeleteStream.t()
    def delete_stream(stream, hard_delete?, expected_version) do
      ExMsg.DeleteStream.new(
        event_stream_id: stream,
        expected_version: expected_version,
        require_master: false,
        hard_delete: hard_delete?
      )
    end
  end

  defmacro __using__(opts) do
    quote do
      use X3m.System.Aggregate.Repo
      require Logger
      alias Banking.EventStore.AggregateRepo.Query

      @extreme Keyword.fetch!(unquote(opts), :extreme)

      @impl X3m.System.Aggregate.Repo
      @spec has?(stream_name :: String.t()) :: boolean()
      def has?(stream) do
        stream
        |> Query.read_events(0, 1)
        |> @extreme.execute()
        |> case do
          {:ok, _} -> true
          _ -> false
        end
      end

      @impl X3m.System.Aggregate.Repo
      @spec delete_stream(
              stream_name :: String.t(),
              hard_delete? :: boolean(),
              expected_version :: integer()
            ) :: :ok
      def delete_stream(stream, hard_delete?, expected_version) do
        stream
        |> Query.delete_stream(hard_delete?, expected_version)
        |> @extreme.execute()
        |> case do
          {:ok, _} -> :ok
          {:error, :NoStream, _} -> :ok
        end
      end

      @impl X3m.System.Aggregate.Repo
      @spec save_events(
              stream_name :: String.t(),
              message :: X3m.System.Message.t(),
              events_metadata :: map()
            ) ::
              {:ok, last_event_number :: integer()}
              | {:error, :wrong_expected_version, expected_version :: integer()}
              | {:error, reason :: any()}
      def save_events(_stream, %X3m.System.Message{events: []} = message, _),
        do: {:ok, message.aggregate_meta.version}

      def save_events(stream, %X3m.System.Message{} = message, events_metadata) do
        stream
        |> Query.write_events(message, events_metadata)
        |> @extreme.execute()
        |> case do
          {:ok, result} ->
            {:ok, result.last_event_number}

          {:error, :WrongExpectedVersion, _} ->
            {:error, :wrong_expected_version, message.aggregate_meta.version}

          other ->
            {:error, other}
        end
      end

      @impl X3m.System.Aggregate.Repo
      def stream_events(stream, start_at \\ 0, per_page \\ 500) do
        Stream.resource(
          fn -> _fetch_stream_events({stream, start_at, per_page, false}) end,
          &_return_stream_events/1,
          fn x -> x end
        )
      end

      defp _fetch_stream_events({stream, start_at, per_page, _is_completed}) do
        Logger.debug(fn ->
          "Taking #{per_page} items starting from #{start_at} for stream: #{inspect(stream)}"
        end)

        {events, is_end_of_stream} =
          stream
          |> Query.read_events(start_at, per_page)
          |> @extreme.execute()
          |> case do
            {:ok, response} ->
              events =
                Enum.map(response.events, fn e ->
                  event_payload = Jason.decode!(e.event.data, keys: :atoms)
                  event_metadata = Jason.decode!(e.event.metadata)

                  event =
                    e.event.event_type
                    |> String.to_atom()
                    |> _create_event(event_payload)

                  {event, e.event.event_number, event_metadata}
                end)

              {events, response.is_end_of_stream}

            {:error, :NoStream, _} ->
              {[], true}

            {:error, :no_stream, _} ->
              {[], true}
          end

        {events, {stream, start_at + per_page, per_page, is_end_of_stream}}
      end

      defp _return_stream_events({[], {_, _, _, is_completed} = params}) when is_completed,
        do: {:halt, params}

      defp _return_stream_events({[], params}) do
        {result, next} = _fetch_stream_events(params)
        {result, {[], next}}
      end

      defp _return_stream_events({events, params}),
        do: {events, {[], params}}

      defp _create_event(event_type, event_payload) when is_atom(event_type) do
        try do
          struct(event_type, event_payload)
        rescue
          UndefinedFunctionError ->
            Logger.warning(
              "Event struct type #{inspect(event_type)} missing, returning payload as tuple"
            )

            {event_type, event_payload}
        end
      end
    end
  end
end
