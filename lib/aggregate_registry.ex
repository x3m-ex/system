defmodule X3m.System.AggregateRegistry do
  @moduledoc !"""
             Internal. Keeps track of registered aggregate pids (per aggregate module) in
             ETS, demonitoring and dropping them when the processes go down.
             """

  require Logger
  use GenServer

  def name(aggregate_mod),
    do: Module.concat(aggregate_mod, PidRegistry)

  ## Client API

  @doc """
  Starts process registry
  """
  def start_link(name),
    do: GenServer.start_link(__MODULE__, name, name: name)

  @doc """
  Returns `true` if `key` is already registered in `server`, `false` otherwise.
  """
  def has_key?(server, key), do: GenServer.call(server, {:has_key?, key})

  @doc """
  Looks up the process pid for `id` stored in `server`.

  Returns `{:ok, pid}` if the one exists, `:error` otherwise.
  """
  def get(server, key),
    do: server |> pid_table |> _get_pid(key)

  @doc """
  Ensures there is a `pid` associated with `key` in `server`.

  Returns :ok once when process is successfully registered
  """
  def register(server, key, pid),
    do: GenServer.call(server, {:register, key, pid})

  @doc """
  Drops `key` from `server` at once, so it no longer resolves.
  """
  @spec unregister(server :: atom(), key :: term()) :: :ok
  def unregister(server, key),
    do: GenServer.call(server, {:unregister, key})

  ## Server Callbacks

  def init(name) do
    name
    |> pid_table
    |> :ets.new([:named_table, read_concurrency: true])

    name
    |> ref_table
    |> :ets.new([:named_table, read_concurrency: true])

    {:ok, %{pid_table: pid_table(name), ref_table: ref_table(name)}}
  end

  ## Private functions

  defp _get_pid(pid_table, key) do
    case :ets.lookup(pid_table, key) do
      [{^key, pid, _ref}] -> {:ok, pid}
      [] -> :error
    end
  end

  defp _get_key(ref_table, ref) do
    case :ets.lookup(ref_table, ref) do
      [{^ref, key}] -> {:ok, key}
      [] -> :error
    end
  end

  defp pid_table(name), do: Module.concat(name, Pids)
  defp ref_table(name), do: Module.concat(name, Refs)

  def handle_call({:has_key?, key}, _from, state) do
    result =
      state.pid_table
      |> _get_pid(key)
      |> case do
        {:ok, _pid} -> true
        :error -> false
      end

    {:reply, result, state}
  end

  def handle_call({:get, key}, _from, state),
    do: {:reply, _get_pid(state.pid_table, key), state}

  def handle_call({:register, key, pid}, _from, state) do
    result =
      case _get_pid(state.pid_table, key) do
        {:ok, pid} ->
          {:error, :key_already_registered, pid}

        :error ->
          ref = Process.monitor(pid)
          true = :ets.insert(state.pid_table, {key, pid, ref})
          true = :ets.insert(state.ref_table, {ref, key})
          :ok
      end

    {:reply, result, state}
  end

  def handle_call({:unregister, key}, _from, state) do
    case :ets.lookup(state.pid_table, key) do
      [{^key, _pid, ref}] ->
        Process.demonitor(ref, [:flush])
        :ets.delete(state.ref_table, ref)
        :ets.delete(state.pid_table, key)

      [] ->
        :ok
    end

    {:reply, :ok, state}
  end

  def handle_info({:DOWN, ref, :process, pid, reason}, state) do
    case _get_key(state.ref_table, ref) do
      {:ok, key} ->
        reason
        |> _down_log_level()
        |> Logger.log(fn -> "Process #{inspect(pid)} went down: #{inspect(reason)}" end)

        :ets.delete(state.ref_table, ref)
        :ets.delete_object(state.pid_table, {key, pid, ref})

      :error ->
        :ok
    end

    {:noreply, state}
  end

  def handle_info(_msg, state), do: {:noreply, state}

  defp _down_log_level(:normal), do: :debug
  defp _down_log_level(:shutdown), do: :debug
  defp _down_log_level({:shutdown, _reason}), do: :debug
  defp _down_log_level(_reason), do: :warning
end
