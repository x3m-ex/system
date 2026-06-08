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

    message
    |> discover_service()
    |> case do
      :not_found ->
        :service_unavailable

      # we can ask any node for authorization
      [{node, mod} | _] ->
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

    message
    |> discover_service()
    |> case do
      :not_found ->
        Instrumenter.execute(
          :service_not_found,
          %{time: DateTime.utc_now(), duration: Instrumenter.duration(mono_start)},
          %{message: message, caller_node: Node.self()}
        )

        _unavailable(message)

      nodes ->
        _try_on_nodes(nodes, message, fn node, mod, message ->
          _dispatch(node, mod, message, timeout, mono_start)
        end)
    end
  end

  defp _try_on_nodes(nodes, message, fun) when is_list(nodes) do
    {message, _} =
      nodes
      |> Enum.shuffle()
      |> Enum.reduce_while({%Message{} = message, []}, fn
        {node, mod}, {%Message{} = message, nodes} ->
          node
          |> fun.(mod, message)
          |> case do
            %Message{response: {:error, {:try_another_node, reason}}} = message ->
              nodes = [{node, reason} | nodes]
              message = %{message | response: {:error, {:no_nodes_available, nodes}}}
              {:cont, {message, nodes}}

            %Message{} = message ->
              {:halt, {message, nil}}
          end
      end)

    message
  end

  @spec discover_service(Message.t()) ::
          :not_found
          | [{:local | atom(), router_mod :: module()}]
  def discover_service(%Message{service_name: service}) do
    service
    |> ServiceRegistry.find_nodes_with_service()
    |> case do
      :not_found -> :not_found
      {:local, {mod, _fun}} -> [{:local, mod}]
      {:remote, nodes} -> Enum.into(nodes, [])
    end
  end

  defp _authorized?(:local, mod, %Message{} = message),
    do: apply(mod, :authorized?, [message])

  defp _authorized?(node, mod, %Message{} = message),
    do: :rpc.call(node, mod, :authorized?, [message])

  defp _dispatch(node, mod, %Message{} = message, timeout, mono_start) do
    Instrumenter.execute(
      :service_found,
      %{time: DateTime.utc_now(), duration: Instrumenter.duration(mono_start)},
      %{message: message, caller_node: Node.self(), service_node: node}
    )

    mono_start = System.monotonic_time()

    Instrumenter.execute(
      :invoking_service,
      %{start: DateTime.utc_now(), mono_start: mono_start},
      %{message: message, caller_node: Node.self(), service_node: node}
    )

    message = _dispatch(node, mod, message, timeout)

    Instrumenter.execute(
      :service_responded,
      %{time: DateTime.utc_now(), duration: Instrumenter.duration(mono_start)},
      %{message: message, caller_node: Node.self(), service_node: node}
    )

    message
  end

  defp _dispatch(:local, mod, %Message{} = message, timeout) do
    # if calling function does something with big binaries, they can leak if
    # caller process is long-lived (refc binary leaks)
    X3m.System.TaskSupervisor
    |> Task.Supervisor.start_child(fn ->
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
