defmodule X3m.System.ClusterCase do
  @moduledoc """
  Helpers for the distributed Dispatcher → Router tests.

  Spins up real peer nodes with `LocalCluster`, each running the `:x3m_system`
  application, and offers small wrappers around `:rpc` for registering routers,
  setting per-node config, waiting for service discovery to propagate, and
  dispatching from a node that does not host the service (so the call really
  crosses the node boundary).
  """
  import ExUnit.Callbacks, only: [on_exit: 1]

  alias X3m.System.ServiceRegistry

  @doc """
  Starts `count` peer nodes running `:x3m_system` and returns their node names.

  The cluster is stopped automatically when the calling test finishes.
  """
  @spec start_nodes(count :: pos_integer(), opts :: Keyword.t()) :: [node()]
  def start_nodes(count, opts \\ []) do
    # A unique prefix per cluster keeps node names from colliding across tests, so a dead
    # node's async cleanup can never race with a same-named node in a later test.
    opts = Keyword.put_new(opts, :applications, [:x3m_system])
    {:ok, cluster} = LocalCluster.start_link(count, opts)
    {:ok, nodes} = LocalCluster.nodes(cluster)

    on_exit(fn ->
      if Process.alive?(cluster), do: LocalCluster.stop(cluster)
      # The async `:node_left` cleanup doesn't reliably run within the fast teardown between
      # tests, so explicitly drop these nodes from this (manager) node's registry. This keeps
      # tests independent — a later test never discovers a previous test's dead nodes.
      Enum.each(nodes, fn node -> send(ServiceRegistry, {:unregister_node_services, node}) end)
    end)

    nodes
  end

  @doc "Registers `router`'s services on `node`, making `node` a provider for them."
  @spec register_router(node(), router :: module()) :: :ok
  def register_router(node, router),
    do: :ok = :rpc.call(node, router, :register_services, [])

  @doc "Sets `:x3m_system` application env `key` to `value` on `node` only."
  @spec put_node_env(node(), key :: atom(), value :: term()) :: :ok
  def put_node_env(node, key, value),
    do: :ok = :rpc.call(node, Application, :put_env, [:x3m_system, key, value])

  @doc """
  Waits until the local (manager) node has discovered `service` as remote, provided by
  exactly `expected_nodes`. Registration auto-broadcasts to connected peers, but
  propagation — and cleanup of dead nodes from earlier tests — is async, so we poll until
  the provider set matches exactly. Matching exactly guarantees a later `Dispatcher.dispatch/1`
  never tries a stale, dead node.
  """
  @spec wait_until_discovered(
          service :: atom(),
          expected_nodes :: [node()],
          timeout :: non_neg_integer()
        ) :: :ok
  def wait_until_discovered(service, expected_nodes, timeout \\ 2_000) do
    expected = Enum.sort(expected_nodes)
    deadline = System.monotonic_time(:millisecond) + timeout
    _wait_until_discovered(service, expected, deadline)
  end

  defp _wait_until_discovered(service, expected, deadline) do
    service
    |> ServiceRegistry.find_nodes_with_service()
    |> case do
      {:remote, nodes} ->
        if Enum.sort(Map.keys(nodes)) == expected do
          :ok
        else
          _retry_discovery(service, expected, deadline)
        end

      _other ->
        _retry_discovery(service, expected, deadline)
    end
  end

  defp _retry_discovery(service, expected, deadline) do
    if System.monotonic_time(:millisecond) >= deadline do
      saw = ServiceRegistry.find_nodes_with_service(service)

      raise "service #{inspect(service)} not discovered as provided by " <>
              "#{inspect(expected)} before timeout; saw #{inspect(saw)}"
    end

    Process.sleep(50)
    _wait_until_discovered(service, expected, deadline)
  end
end
