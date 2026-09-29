defmodule X3m.System.Dispatcher do
  @moduledoc """
  Sends a `X3m.System.Message` to whichever node offers its service and waits for the
  response.

  This is the client-facing entry point of the messaging layer. You build a message
  with `X3m.System.Message.new/2`, optionally `assign` values onto it, and then call
  `dispatch/2`:

      :open_account
      |> X3m.System.Message.new(raw_request: %{"id" => id})
      |> X3m.System.Dispatcher.dispatch()

  Service discovery is transparent: the dispatcher asks the (internal) service
  registry which nodes provide `message.service_name`. A **local** provider is invoked
  in a supervised task; **remote** providers are invoked over `:erpc` from one. The reply
  is delivered back to the calling process, so `dispatch/2` returns the resolved
  `X3m.System.Message` with its `response` set. See the "Distribution" guide for how nodes are chosen and
  how a service can ask the dispatcher to `:try_another_node`.

  Using the dispatcher does **not** require aggregates or event sourcing — any module
  registered through `X3m.System.Router` can be a dispatch target.
  """
  alias X3m.System.{Message, Response, Instrumenter, ServiceRegistry}

  @type authorization :: boolean() | :service_unavailable | {:error, {:badrpc, reason :: term()}}

  # the remote call outlasts the dispatch timeout, so the caller's timeout always fires first
  @remote_timeout_margin_ms 1_000

  @doc """
  Returns whether the (discovered) service authorizes `message`.

  Discovery is performed first; if no node offers the service `:service_unavailable`
  is returned. Otherwise authorization is delegated to the providing node's router
  (`X3m.System.Router` `authorize/1`).

  Options:

    * `:timeout` - milliseconds to wait for a remote node's answer (default `5_000`).
      Each provider tried gets the full timeout, so the worst case is providers x timeout.

  If a remote node fails the check (it times out, goes down, or its `authorize/1`
  raises, exits or throws), the next providing node is asked. When every one fails,
  `{:error, {:badrpc, reason}}` of the last one is returned.
  """
  @spec authorized?(Message.t()) :: authorization()
  @spec authorized?(Message.t(), opts :: Keyword.t()) :: authorization()
  def authorized?(%Message{} = message, opts \\ []) do
    timeout = Keyword.get(opts, :timeout, 5_000)
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

      nodes ->
        _authorized_on_nodes(nodes, message, timeout)
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

  @doc """
  Discovers a node offering `message.service_name`, invokes the service there and
  returns the resolved `message` with its `response` set.

  A halted message (`halted?: true`) is returned untouched.

  Options:

    * `:timeout` - milliseconds to wait for the service reply (default `5_000`). On
      expiry the response is set to `Response.service_timeout/3`, even if the handler
      is still running; a later reply is discarded. The handler, local or remote, is
      not cancelled: a provider should bound its own work, or hung handlers pile up
      at the callers' dispatch rate.

  If no node offers the service the response is set to `Response.service_unavailable/1`.
  When several nodes offer it, one is picked at random; a node may reply with
  `{:error, {:try_another_node, reason}}` to make the dispatcher try the next one.
  If the handler raises, exits or throws, local or remote, or the remote node goes
  down, the response is `{:error, {:badrpc, reason}}` at once. If a service,
  local or remote, returns other than `:ok`, the response is
  `{:error, {:badrpc, {:bad_return, value}}}`.
  """
  @spec dispatch(Message.t()) :: Message.t()
  @spec dispatch(Message.t(), opts :: Keyword.t()) :: Message.t()
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

  @doc """
  Looks up which nodes offer `message.service_name`.

  Returns `:not_found` when no node provides it, or a list of
  `{:local | node, router_module}` pairs otherwise. Used internally by `dispatch/2`
  and `authorized?/1`; exposed for introspection.
  """
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

  # any providing node can answer, and a check has no side effects, so a failure moves on
  defp _authorized_on_nodes([{node, mod} | nodes], %Message{} = message, timeout) do
    node
    |> _authorized?(mod, message, timeout)
    |> case do
      {:badrpc, reason} when nodes == [] -> {:error, {:badrpc, reason}}
      {:badrpc, _reason} -> _authorized_on_nodes(nodes, message, timeout)
      authorized? -> authorized?
    end
  end

  defp _authorized?(:local, mod, %Message{} = message, _timeout),
    do: apply(mod, :authorized?, [message])

  defp _authorized?(node, mod, %Message{} = message, timeout),
    do: _erpc_call(node, mod, :authorized?, [message], timeout)

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

  # A relay process invokes the service and receives its reply, so the caller's timeout
  # holds even when the invocation blocks, and a late reply dies with the relay.
  defp _dispatch(node, mod, %Message{} = message, timeout) do
    caller = self()
    tag = make_ref()

    {:ok, relay} =
      X3m.System.TaskSupervisor
      |> Task.Supervisor.start_child(fn -> _relay(caller, tag, node, mod, message, timeout) end)

    relay_monitor = Process.monitor(relay)

    receive do
      {^tag, %Message{} = reply} ->
        Process.demonitor(relay_monitor, [:flush])
        %{reply | reply_to: caller}

      {^tag, {:badrpc, reason}} ->
        Process.demonitor(relay_monitor, [:flush])
        Message.error(message, {:badrpc, reason})

      # a relay sends before it exits normally, so its DOWN only arrives first on a crash
      {:DOWN, ^relay_monitor, :process, _relay, reason} ->
        Message.error(message, {:badrpc, {:EXIT, reason}})
    after
      timeout ->
        _stop_relay(relay, relay_monitor, tag)
        response = Response.service_timeout(message.service_name, message.id, timeout)

        Message.return(message, response)
    end
  end

  defp _relay(caller, tag, node, mod, %Message{} = message, timeout) do
    caller_monitor = Process.monitor(caller)
    message = %{message | reply_to: self()}

    node
    |> _invoke(mod, message, timeout)
    |> case do
      {:returned, :ok} -> _forward_reply(caller, caller_monitor, tag, message.id, nil)
      {:returned, value} -> send(caller, {tag, {:badrpc, {:bad_return, value}}})
      {:handler, monitor} -> _forward_reply(caller, caller_monitor, tag, message.id, monitor)
      {:badrpc, reason} -> send(caller, {tag, {:badrpc, reason}})
    end
  end

  # own unlinked task, so like a remote handler it outlives the relay when the dispatch
  # times out; monitored from its spawn, so its crash is reported as a remote one is
  defp _invoke(:local, mod, %Message{} = message, _timeout) do
    %Task{ref: handler_monitor} =
      X3m.System.TaskSupervisor
      |> Task.Supervisor.async_nolink(fn -> apply(mod, message.service_name, [message]) end)

    {:handler, handler_monitor}
  end

  # bounded, so an orphaned relay stops; tagged, so a service return is never read as ours
  defp _invoke(node, mod, %Message{} = message, timeout) do
    remote_timeout = _remote_timeout(timeout)
    returned = :erpc.call(node, mod, message.service_name, [message], remote_timeout)
    {:returned, returned}
  catch
    kind, reason -> {:badrpc, _badrpc_reason(kind, reason)}
  end

  defp _erpc_call(node, mod, fun, args, timeout) do
    :erpc.call(node, mod, fun, args, timeout)
  catch
    kind, reason -> {:badrpc, _badrpc_reason(kind, reason)}
  end

  defp _remote_timeout(:infinity), do: :infinity
  defp _remote_timeout(timeout), do: timeout + @remote_timeout_margin_ms

  # same shapes as `:rpc.call/5`, plus `{:throw, value}` where `:rpc` returns the value
  defp _badrpc_reason(:error, {:erpc, :noconnection}), do: :nodedown
  defp _badrpc_reason(:error, {:erpc, :timeout}), do: :timeout
  defp _badrpc_reason(:error, {:erpc, :notsup}), do: :notsup
  defp _badrpc_reason(:error, {:erpc, reason}), do: {:EXIT, reason}
  defp _badrpc_reason(:error, {:exception, reason, stack}), do: {:EXIT, {reason, stack}}
  defp _badrpc_reason(:exit, {:exception, reason}), do: {:EXIT, reason}
  defp _badrpc_reason(:exit, {:signal, reason}), do: {:EXIT, reason}
  defp _badrpc_reason(:throw, value), do: {:throw, value}

  # a reply the handler sends itself arrives before its DOWN; after a normal exit another
  # process may still answer, so only a crash ends the wait
  defp _forward_reply(caller, caller_monitor, tag, message_id, handler_monitor) do
    receive do
      %Message{id: ^message_id} = reply ->
        send(caller, {tag, reply})

      {^handler_monitor, :ok} ->
        _forward_reply(caller, caller_monitor, tag, message_id, handler_monitor)

      {^handler_monitor, returned} ->
        send(caller, {tag, {:badrpc, {:bad_return, returned}}})

      {:DOWN, ^caller_monitor, :process, _caller, _reason} ->
        :ok

      {:DOWN, ^handler_monitor, :process, _handler, :normal} ->
        _forward_reply(caller, caller_monitor, tag, message_id, nil)

      {:DOWN, ^handler_monitor, :process, _handler, reason} ->
        send(caller, {tag, {:badrpc, _crash_reason(reason)}})
    end
  end

  # same shapes as a remote handler's crash
  defp _crash_reason({{:nocatch, value}, _stack}), do: {:throw, value}
  defp _crash_reason(reason), do: {:EXIT, reason}

  # DOWN arrives after anything the relay sent, so the flush below catches a reply in flight.
  defp _stop_relay(relay, relay_monitor, tag) do
    Process.exit(relay, :kill)

    receive do
      {:DOWN, ^relay_monitor, :process, _relay, _reason} -> :ok
    end

    receive do
      {^tag, _reply} -> :ok
    after
      0 -> :ok
    end
  end

  defp _unavailable(%Message{service_name: service_name} = message) do
    response = Response.service_unavailable(service_name)

    Message.return(message, response)
  end
end
