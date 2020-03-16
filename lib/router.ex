defmodule X3m.System.Router do
  @moduledoc """
  Registers system wide services.

  Each `service/2` macro registers system-wide service and function with
  documentation in module that `uses` this module.

  Service functions invoke function of the same name of specified module.
  If result of that invocation is `{:reply, %X3m.System.Message{}}`, 
  it sends message to `message.reply_to` pid.

  If result of invocation is `:noreply`, nothing is sent to that pid.

  In any case function returns `:ok`.

  ## Examples

  ### Defining router

      defmodule MyRouter do
        use X3m.System.Router

        @servicedoc false
        service :create_user, MessageHandler

        @servicedoc \"""
        overridden!
        \"""
        service :get_user, MessageHandler

        service :edit_user, MessageHandler
      end


  ### Getting registered services

      iex> MyRouter.registered_services()
      [create_user: 1, get_user: 1, edit_user: 1]

  ### Invoking service as a function

      iex> :create_user |>
      ...>   X3m.System.Message.new() |>
      ...>   MyRouter.create_user()
      :ok
  """
  require Logger
  alias X3m.System.Message

  defmacro service(service_name, message_handler, f) do
    quote do
      case(@servicedoc) do
        nil ->
          @doc """
          Accepts `#{unquote(service_name)}` service call, routing it's `message` to 
          `#{unquote(message_handler)}.#{unquote(f)}/1`.

          If result of that invocation is `{:reply, %X3m.System.Message{}}`, 
          it sends message to `message.reply_to` pid.

          If result of invocation is `:noreply`, nothing is sent to that pid.

          In any case function returns `:ok`.

          ## Example:

              iex> #{inspect(unquote(service_name))} |>
              ...>   X3m.System.Message.new() |>
              ...>   #{__MODULE__}.#{unquote(service_name)}()
              :ok
          """

        other ->
          @doc other
      end

      @x3m_service [{unquote(service_name), 1}]
      @spec unquote(service_name)(Message.t()) :: :ok
      def unquote(service_name)(%Message{service_name: unquote(service_name)} = message) do
        Logger.metadata(message.logger_metadata)

        X3m.System.Instrumenter.execute(:service_request_received, %{}, %{
          service: unquote(service_name)
        })

        message
        |> choose_node()
        |> _invoke(unquote(message_handler), unquote(f), message)
      end

      @servicedoc nil
    end
  end

  defmacro service(service_name, message_handler) do
    quote do
      service(unquote(service_name), unquote(message_handler), unquote(service_name))
    end
  end

  defmacro __using__(_opts) do
    quote do
      alias X3m.System.Router
      require Router
      import Router

      Module.register_attribute(
        __MODULE__,
        :x3m_service,
        accumulate: true,
        persist: true
      )

      @servicedoc nil

      @doc !"""
           Returns list of service functions with their arrity.
           """
      @spec registered_services :: [{:atom, non_neg_integer}]
      def registered_services do
        __MODULE__.__info__(:attributes)
        |> Keyword.get_values(:x3m_service)
        |> List.flatten()
      end

      @doc !"""
           Sends internal event for each service to be registered in runtime.
           """
      @spec register_services :: :ok
      def register_services do
        services =
          registered_services()
          |> Enum.map(fn {service, _arrity} -> {service, __MODULE__} end)
          |> Enum.into(%{})

        X3m.System.Instrumenter.execute(:register_local_services, %{}, %{services: services})
        :ok
      end

      @doc false
      @spec _invoke(:local | node(), atom, atom, Message.t()) :: :ok
      def _invoke(node, message_handler, f, message)

      def _invoke(:local, message_handler, f, message) do
        Logger.metadata(message.logger_metadata)
        mono_start = System.monotonic_time()

        X3m.System.Instrumenter.execute(
          :invoking_service,
          %{start: DateTime.utc_now(), mono_start: mono_start},
          %{
            node: Node.self(),
            service: message.service_name
          }
        )

        case apply(message_handler, f, [message]) do
          {:reply, %Message{} = message} ->
            send(message.reply_to, message)

            X3m.System.Instrumenter.execute(
              :service_responded,
              %{
                time: DateTime.utc_now(),
                duration: X3m.System.Instrumenter.duration(mono_start, :microsecond)
              },
              %{message: message}
            )

            :ok

          :noreply ->
            :ok
        end
      end

      def _invoke(node, message_handler, f, message) do
        true =
          :rpc.cast(node, __MODULE__, :_invoke, [
            :local,
            message_handler,
            f,
            message
          ])

        :ok
      end

      @doc !"""
           Choose node on which MFA will be applied.

           This is optional callback. By default it will return `:local`,
           meaning that `sys_msg` will be handled by local module.

           It can be overriden like:

           ```
           def choose_node(%X3m.System.Message{}) do
             [:jobs_1@my_comp_name, :local] |> Enum.random()
           end
           ```
           """
      @spec choose_node(Message.t()) :: :local | node()
      def choose_node(_sys_msg),
        do: :local

      defoverridable choose_node: 1
    end
  end
end
