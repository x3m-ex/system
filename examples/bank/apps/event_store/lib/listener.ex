defmodule Banking.EventStore.Listener do
  @moduledoc !"""
             Macro for defining event listeners that subscribe to EventStore streams.

             Provides the `on_event/2` macro to map event types to dispatch service names:

                 use Banking.EventStore.Listener,
                   stream: "$ce-accounts",
                   db_repo: Banking.Listeners.Repo,
                   module_name: "Banking.Listeners.Accounts.Listener"

                 on_event Banking.Core.Aggregates.Account.Events.Opened, dispatch: :account_opened!
             """

  defmacro on_event(event_type, opts \\ []) do
    service_name = Keyword.fetch!(opts, :dispatch)

    quote do
      def process_event(unquote(event_type), %X3m.System.Message{} = msg) do
        msg
        |> X3m.System.Message.to_service(unquote(service_name))
        |> Map.put(:logger_metadata, Logger.metadata())
        |> X3m.System.Dispatcher.dispatch()
        |> case do
          %X3m.System.Message{response: :ok} = msg ->
            msg

          %X3m.System.Message{response: {:ok, ver}} = msg when is_integer(ver) ->
            msg

          %X3m.System.Message{response: {:created, id}} = msg when is_binary(id) ->
            msg

          %X3m.System.Message{response: {:created, id, ver}} = msg
          when is_binary(id) and is_integer(ver) ->
            msg
        end
      end
    end
  end

  defmacro __using__(opts) do
    db_repo = Keyword.fetch!(opts, :db_repo)
    stream = Keyword.fetch!(opts, :stream)

    quote location: :keep do
      use Extreme.Listener
      require Logger
      require Banking.EventStore.Listener
      import Banking.EventStore.Listener
      alias X3m.System.Message, as: SysMsg

      @module_name Keyword.get(unquote(opts), :module_name, __MODULE__) |> to_string()

      def child_spec([extreme | opts]) do
        %{
          id: __MODULE__,
          start: {__MODULE__, :start_link, [extreme, unquote(stream), opts]}
        }
      end

      @spec get_last_event(stream_name :: String.t()) :: integer()
      defp get_last_event(stream_name) do
        unquote(db_repo)
        |> Process.whereis()
        |> case do
          nil ->
            Process.sleep(100)
            get_last_event(stream_name)

          _pid ->
            Banking.EventStore.DB.get_last_event(
              unquote(db_repo),
              @module_name,
              stream_name
            )
        end
      end

      @spec process_push(push :: map(), stream_name :: String.t()) ::
              {:ok, event_number :: integer()}
      defp process_push(
             %{event: %{data: nil}, link: %{event_number: link_event_number}},
             stream_name
           ) do
        :ok =
          Banking.EventStore.DB.ack_event(
            unquote(db_repo),
            @module_name,
            stream_name,
            link_event_number
          )

        {:ok, link_event_number}
      end

      defp process_push(push, stream_name) do
        link_event_number = push.link.event_number
        event_number = push.event.event_number
        event_type = String.to_atom(push.event.event_type)

        data = Jason.decode!(push.event.data, keys: :atoms)
        metadata = _get_metadata(push.event.metadata)
        correlation_id = Map.get(metadata, :"$correlationId")
        causation_id = Map.get(metadata, :"$id")
        emitted_at = Map.get(metadata, :emitted_at)

        logger_metadata =
          Logger.metadata()
          |> Keyword.put(:corr_id, correlation_id)
          |> Keyword.put(:caus_id, causation_id)

        Logger.metadata(logger_metadata)

        msg =
          :on_event
          |> SysMsg.new(
            raw_request: data,
            correlation_id: correlation_id,
            causation_id: causation_id,
            logger_metadata: logger_metadata
          )
          |> SysMsg.assign(:on_event, event_type)
          |> SysMsg.assign(:event_number, event_number)
          |> SysMsg.assign(:link_event_number, link_event_number)
          |> SysMsg.assign(:emitted_at, emitted_at)
          |> SysMsg.assign(:event_data, data)
          |> SysMsg.assign(:invoked_by, %{system?: true})

        Banking.EventStore.DB.in_transaction(unquote(db_repo), fn ->
          %SysMsg{} = process_event(event_type, msg)

          :ok =
            Banking.EventStore.DB.ack_event(
              unquote(db_repo),
              @module_name,
              stream_name,
              link_event_number
            )

          Logger.debug(fn -> "#{__MODULE__} processed event ##{event_number}" end)
        end)

        {:ok, link_event_number}
      end

      defp _get_metadata(nil), do: %{}

      defp _get_metadata(metadata),
        do: Jason.decode!(metadata, keys: :atoms)

      @before_compile Banking.EventStore.Listener
    end
  end

  defmacro __before_compile__(_env) do
    quote do
      @spec process_event(event_type :: atom(), msg :: X3m.System.Message.t()) ::
              X3m.System.Message.t()
      def process_event(event_type, msg) do
        Logger.debug(fn -> "#{__MODULE__} skipping event #{event_type}" end)
        X3m.System.Message.return(msg, :ok)
      end
    end
  end
end
