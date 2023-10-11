defmodule X3m.System.ServiceRegistry do
  use GenServer
  require Logger
  alias X3m.System.ServiceRegistry.Implementation, as: Impl
  alias X3m.System.ServiceRegistry.State

  def start_link(opts \\ []),
    do: GenServer.start_link(__MODULE__, :ok, [{:name, __MODULE__} | opts])

  def find_nodes_with_service(service),
    do: GenServer.call(__MODULE__, {:find_nodes_with_service, service})

  @doc false
  def handle_event([:x3m, :system, :register_local_services], _measurements, payload, _config),
    do: send(__MODULE__, {:register_local_services, payload})

  ## Server side

  @impl GenServer
  def init(:ok) do
    Process.flag(:trap_exit, true)
    :ok = _subscribe_for_service_events()
    interval = 20_000
    Process.send_after(self(), {:exchange_services, interval}, interval)

    {:ok, %State{services: %State.Services{local: %{}, public: %{}, remote: %{}}}}
  end

  @impl GenServer
  def handle_call({:find_nodes_with_service, service}, _from, %State{} = state) do
    response =
      case state.services do
        %{local: %{^service => mod}} ->
          {:local, {mod, service}}

        %{remote: %{^service => nodes}} ->
          {:remote, nodes}

        _ ->
          Logger.warning(fn -> "[Discovery] Service #{service} NOT found!" end)
          :not_found
      end

    {:reply, response, state}
  end

  @impl GenServer
  def handle_info({:register_local_services, %{} = local_services}, state) do
    Logger.debug(fn -> "[Discovery] Registered local services #{inspect(local_services)}" end)

    request = {:register_remote_services, {Node.self(), local_services.public}}

    Logger.debug(fn -> "[Discovery] Notifying cluster members of new local services" end)

    Node.list()
    |> Enum.each(fn node -> send({__MODULE__, node}, request) end)

    all_local_services =
      state.services.local
      |> Map.merge(local_services.private)
      |> Map.merge(local_services.public)

    services = %State.Services{
      state.services
      | local: all_local_services,
        public: local_services.public
    }

    {:noreply, %State{state | services: services}}
  end

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
    {:noreply, state}
  end

  def handle_info({:unregister_node_services, node}, state) do
    Logger.debug(fn -> "[Discovery] Unregistering node services #{inspect(node)}" end)
    remote_services = Impl.remove_remote_services(state.services.remote, node)
    services = %State.Services{state.services | remote: remote_services}

    {:noreply, %State{state | services: services}}
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
end
