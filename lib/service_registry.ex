defmodule X3m.System.ServiceRegistry do
  @moduledoc !"""
             Internal. Cluster-wide registry of which node offers which service; exchanges
             local/remote service maps between nodes and is the only writer of the ETS table
             that `X3m.System.Dispatcher` reads to discover services.
             """
  use GenServer
  require Logger
  alias X3m.System.ServiceRegistry.Implementation, as: Impl
  alias X3m.System.ServiceRegistry.State

  @table Module.concat(__MODULE__, Services)

  def start_link(opts \\ []),
    do: GenServer.start_link(__MODULE__, :ok, [{:name, __MODULE__} | opts])

  @doc """
  Looks up which node offers `service`, reading the registry's table without a call to
  the registry process.

  Returns `{:local, {module, service}}`, `{:remote, %{node => module}}`, or `:not_found`
  when no node offers it or the registry is not running.

      {:remote,
       %{
         engine_1@localhost: Engine.X3m.Router,
         engine_2@localhost: Engine.X3m.Router
       }}
  """
  @spec find_nodes_with_service(service :: atom()) ::
          {:local, {router_mod :: module(), service :: atom()}}
          | {:remote, %{node() => router_mod :: module()}}
          | :not_found
  def find_nodes_with_service(service) do
    service
    |> _lookup()
    |> case do
      :not_found ->
        Logger.warning(fn -> "[Discovery] Service #{service} NOT found!" end)
        :not_found

      :registry_not_running ->
        Logger.warning(fn ->
          "[Discovery] Service registry is not running, service #{service} NOT found!"
        end)

        :not_found

      found ->
        found
    end
  end

  # runs in the registering process, so its services are discoverable once it returns
  @doc false
  def handle_event([:x3m, :system, :register_local_services], _measurements, payload, _config),
    do: GenServer.call(__MODULE__, {:register_local_services, payload}, :infinity)

  ## Server side

  @impl GenServer
  def init(:ok) do
    Process.flag(:trap_exit, true)
    :ok = _subscribe_for_service_events()
    interval = 20_000
    Process.send_after(self(), {:exchange_services, interval}, interval)
    _table = :ets.new(@table, [:named_table, read_concurrency: true])

    {:ok, %State{services: %State.Services{local: %{}, public: %{}, remote: %{}}}}
  end

  @impl GenServer
  def handle_call({:register_local_services, %{} = local_services}, _from, %State{} = state) do
    Logger.debug(fn -> "[Discovery] Registered local services #{inspect(local_services)}" end)

    request = {:register_remote_services, {Node.self(), local_services.public}}

    Logger.debug(fn -> "[Discovery] Notifying cluster members of new local services" end)

    Node.list()
    |> Enum.each(fn node -> send({__MODULE__, node}, request) end)

    all_local_services =
      state.services.local
      |> Map.merge(local_services.private)
      |> Map.merge(local_services.public)

    services = %{
      state.services
      | local: all_local_services,
        public: local_services.public
    }

    :ok = _publish(services)
    {:reply, :ok, %{state | services: services}}
  end

  @impl GenServer
  def handle_info({:exchange_services, interval}, %State{} = state) do
    # Logger.debug(fn -> "[Discovery] Exchanging services with cluster members..." end)
    request = {:register_remote_services, {Node.self(), state.services.public}}

    Node.list()
    |> Enum.each(fn node -> send({__MODULE__, node}, request) end)

    Process.send_after(self(), {:exchange_services, interval}, interval)

    {:noreply, state}
  end

  def handle_info({:register_remote_services, {node, services}}, %State{} = state) do
    # Logger.debug(fn -> "[Discovery] Registering local services for node #{inspect(node)}" end)
    {:ok, %State{} = state} = Impl.register_remote_services({node, services}, state)
    :ok = _publish(state.services)
    {:noreply, state}
  end

  def handle_info({:unregister_node_services, node}, %State{} = state) do
    Logger.debug(fn -> "[Discovery] Unregistering node services #{inspect(node)}" end)
    remote_services = Impl.remove_remote_services(state.services.remote, node)
    services = %{state.services | remote: remote_services}

    :ok = _publish(services)
    {:noreply, %{state | services: services}}
  end

  def handle_info(
        {:introduce_local_services, node},
        %State{services: %State.Services{public: public_services}} = state
      ) do
    Logger.debug(fn -> "[Discovery] Introducing local services to #{inspect(node)}" end)
    request = {:register_remote_services, {Node.self(), public_services}}
    send({__MODULE__, node}, request)
    {:noreply, state}
  end

  @impl GenServer
  def terminate(reason, %State{}) do
    Logger.info(fn -> "Terminating ServiceRegistry because of: #{inspect(reason)}" end)
    request = {:unregister_node_services, Node.self()}

    Node.list()
    |> Enum.each(fn node -> send({__MODULE__, node}, request) end)

    Process.sleep(10_000)
    :ok
  end

  defp _subscribe_for_service_events(config \\ nil) do
    events = [
      [:x3m, :system, :register_local_services]
    ]

    :telemetry.attach_many("x3m-system-services", events, &__MODULE__.handle_event/4, config)
  end

  # a local provider wins over remote ones, as the dispatcher invokes it directly
  defp _publish(%State.Services{local: local, remote: remote}) do
    remote_entries = Map.new(remote, fn {service, nodes} -> {service, {:remote, nodes}} end)
    local_entries = Map.new(local, fn {service, mod} -> {service, {:local, {mod, service}}} end)
    entries = Map.merge(remote_entries, local_entries)
    rows = Map.to_list(entries)

    true = :ets.insert(@table, rows)

    @table
    |> :ets.select([{{:"$1", :_}, [], [:"$1"]}])
    |> Enum.reject(&Map.has_key?(entries, &1))
    |> Enum.each(&:ets.delete(@table, &1))
  end

  # the table dies with the registry, so a stopped registry offers no services
  defp _lookup(service) do
    @table
    |> :ets.lookup(service)
    |> case do
      [{^service, found}] -> found
      [] -> :not_found
    end
  rescue
    ArgumentError -> :registry_not_running
  end
end
