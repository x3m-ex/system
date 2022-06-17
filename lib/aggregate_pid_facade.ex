defmodule X3m.System.AggregatePidFacade do
  use GenServer
  require Logger
  alias X3m.System.AggregateSup
  alias X3m.System.AggregateRegistry, as: Registry

  def name(aggregate_mod),
    do: Module.concat(aggregate_mod, PidFacade)

  def get_aggregate_mod,
    do: X3m.System.GenAggregate

  ## Client API

  def start_link(aggregate_mod),
    do: GenServer.start_link(__MODULE__, aggregate_mod, name: name(aggregate_mod))

  def get_pid(server, key, when_not_registered),
    do: GenServer.call(server, {:get_pid, key, when_not_registered})

  def spawn_new(server, key, opts \\ []),
    do: GenServer.call(server, {:spawn_new, key, opts})

  def exit_process(server, key, reason),
    do: GenServer.cast(server, {:exit_process, key, reason})

  @impl GenServer
  def init(aggregate_mod) do
    state = %{
      registry: Registry.name(aggregate_mod),
      aggregate_sup: AggregateSup.name(aggregate_mod),
      aggregate_mod: aggregate_mod
    }

    {:ok, state}
  end

  @impl GenServer
  def handle_call({:spawn_new, key, opts}, _from, state) do
    response = _spawn_new(key, state, opts)
    {:reply, response, state}
  end

  def handle_call({:get_pid, key, when_not_registered}, _from, state),
    do: {:reply, _get_pid(key, state, when_not_registered, []), state}

  @impl GenServer
  def handle_cast({:exit_process, key, reason}, state) do
    case Registry.get(state.registry, key) do
      {:ok, pid} ->
        Logger.debug("Killing process #{inspect(pid)}: #{inspect(reason)}")
        AggregateSup.terminate_child(state.aggregate_sup, pid)

      _ ->
        :ok
    end

    {:noreply, state}
  end

  @impl GenServer
  def handle_info({:exit_process, pid, reason}, state) do
    Logger.info("Killing process #{inspect(pid)}: #{inspect(reason)}")
    AggregateSup.terminate_child(state.aggregate_sup, pid)

    {:noreply, state}
  end

  defp _get_pid(key, state, when_not_registered, opts) do
    case Registry.get(state.registry, key) do
      :error ->
        when_not_registered.(state.aggregate_mod, key, fn ->
          _spawn_new(key, state, opts)
        end)

      {:ok, pid} ->
        {:ok, pid}
    end
  end

  defp _spawn_new(key, state, opts) do
    {:ok, pid} = AggregateSup.start_child(state.aggregate_sup, opts)
    X3m.System.Instrumenter.execute(:new_aggr_spawned, %{}, %{id: key})

    case Registry.register(state.registry, key, pid) do
      :ok -> {:ok, pid}
      other -> other
    end
  end
end
