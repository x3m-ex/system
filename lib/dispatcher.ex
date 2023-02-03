defmodule X3m.System.Dispatcher do
  alias X3m.System.{Message, Response, Instrumenter, ServiceRegistry}

  @spec authorized?(Message.t()) :: boolean() | {:service_unavailable, atom}
  def authorized?(%Message{} = message) do
    mono_start = System.monotonic_time()
    message = %{message | invoked_at: DateTime.utc_now(), reply_to: self()}

    Instrumenter.execute(
      :checking_if_service_call_is_authorized,
      %{start: DateTime.utc_now(), mono_start: mono_start},
      %{message: message, caller_node: Node.self()}
    )

    case discover_service(message) do
      {:unavailable, _message} ->
        :service_unavailable

      {node, mod} ->
        _authorized?(node, mod, message)
    end
  end

  @doc """
  Sets `message.dry_run` to `true` if it was (by default) `false`
  and dispatches service call.

  Pay attention if you have some side effects (like persistence of unique values in DB)
  in your command handling. Such validations should be either avoided or
  Aggregate needs to implement `rollback/2` and `commit/2` callbacks.

  If service call is valid, `message.response` will be in `{:ok, aggregate_version}` format,
  otherwise response will have error message as it would have if dispatch was called.
  """
  @spec validate(Message.t()) :: Message.t()
  def validate(%Message{dry_run: false} = message) do
    message
    |> Map.put(:dry_run, true)
    |> dispatch()
  end

  def validate(%Message{} = message),
    do: dispatch(message)

  def dispatch(%Message{halted?: true} = message), do: message

  def dispatch(%Message{} = message, opts \\ []) do
    timeout = Keyword.get(opts, :timeout, 5_000)
    mono_start = System.monotonic_time()
    message = %{message | invoked_at: DateTime.utc_now(), reply_to: self()}

    Instrumenter.execute(
      :discovering_service,
      %{start: DateTime.utc_now(), mono_start: mono_start},
      %{message: message, caller_node: Node.self()}
    )

    case discover_service(message) do
      {:unavailable, message} ->
        Instrumenter.execute(
          :service_not_found,
          %{time: DateTime.utc_now(), duration: Instrumenter.duration(mono_start)},
          %{message: message, caller_node: Node.self()}
        )

        _unavailable(message)

      {node, mod} ->
        Instrumenter.execute(
          :service_found,
          %{time: DateTime.utc_now(), duration: Instrumenter.duration(mono_start)},
          %{message: message, caller_node: Node.self(), service_node: node}
        )

        _dispatch(node, mod, message, timeout)
    end
  end

  @spec discover_service(Message.t()) :: {:unavailable, Message.t()} | {node | :local, atom}
  def discover_service(%Message{service_name: service} = message) do
    case ServiceRegistry.find_nodes_with_service(service) do
      :not_found -> {:unavailable, message}
      {:local, {mod, _fun}} -> {:local, mod}
      {:remote, nodes} -> Enum.random(nodes)
    end
  end

  defp _authorized?(:local, mod, %Message{} = message),
    do: apply(mod, :authorized?, [message])

  defp _authorized?(node, mod, %Message{} = message),
    do: :rpc.call(node, mod, :authorized?, [message])

  defp _dispatch(:local, mod, %Message{} = message, timeout) do
    # if calling function does something with big binaries, they can leak if
    # caller process is long-lived (refc binary leaks)
    spawn(fn ->
      :ok = apply(mod, message.service_name, [message])
    end)

    _wait_for_response(message, timeout)
  end

  defp _dispatch(node, mod, %Message{} = message, timeout) do
    :ok = :rpc.call(node, mod, message.service_name, [message])
    _wait_for_response(message, timeout)
  end

  defp _wait_for_response(%Message{id: message_id} = message, timeout) do
    receive do
      %Message{id: ^message_id} = message -> message
    after
      timeout ->
        response = Response.service_timeout(message.service_name, message.id, timeout)

        Message.return(message, response)
    end
  end

  defp _unavailable(%Message{service_name: service_name} = message) do
    response = Response.service_unavailable(service_name)

    Message.return(message, response)
  end
end
