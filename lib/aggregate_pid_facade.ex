defmodule X3m.System.AggregatePidFacade do
  @moduledoc !"""
             Internal. Default `pid_facade_mod` for message handlers: spawns, locates and
             tears down per-id aggregate processes via the aggregate registry and supervisor.
             """
  use GenServer
  require Logger
  alias X3m.System.AggregateSup
  alias X3m.System.AggregateRegistry, as: Registry

  @state_key {__MODULE__, :state}

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

  # inline inside the facade itself, e.g. from a when_pid_is_not_registered/3 override
  def exit_process(server, key, reason) do
    server
    |> GenServer.whereis()
    |> case do
      facade when facade == self() ->
        @state_key
        |> Process.get()
        |> _exit_process(key, reason)

      _facade ->
        GenServer.call(server, {:exit_process, key, reason})
    end
  end

  @impl GenServer
  def init(aggregate_mod) do
    state = %{
      registry: Registry.name(aggregate_mod),
      aggregate_sup: AggregateSup.name(aggregate_mod),
      aggregate_mod: aggregate_mod
    }

    # read by exit_process/3 inside the facade; keep in sync if a callback ever changes state
    Process.put(@state_key, state)

    {:ok, state}
  end

  @impl GenServer
  def handle_call({:spawn_new, key, opts}, _from, state) do
    response = _spawn_new(key, state, opts)
    {:reply, response, state}
  end

  def handle_call({:get_pid, key, when_not_registered}, _from, state),
    do: {:reply, _get_pid(key, state, when_not_registered, []), state}

  def handle_call({:exit_process, key, reason}, _from, state),
    do: {:reply, _exit_process(state, key, reason), state}

  @impl GenServer
  def handle_info({:exit_process, pid, reason}, state) do
    Logger.info("Killing process #{inspect(pid)}: #{inspect(reason)}")
    AggregateSup.terminate_child(state.aggregate_sup, pid)

    {:noreply, state}
  end

  # unregister first so the id never resolves to a terminating pid
  defp _exit_process(state, key, reason) do
    case Registry.get(state.registry, key) do
      {:ok, pid} ->
        Logger.debug("Killing process #{inspect(pid)}: #{inspect(reason)}")
        :ok = Registry.unregister(state.registry, key)
        AggregateSup.terminate_child(state.aggregate_sup, pid)
        :ok

      :error ->
        :ok
    end
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
