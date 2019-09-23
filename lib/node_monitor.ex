defmodule X3m.System.NodeMonitor do
  def child_spec(_opts) do
    %{
      id: __MODULE__,
      start: {__MODULE__, :start_link, []},
      type: :worker,
      restart: :permanent,
      shutdown: 500
    }
  end

  def start_link do
    {:ok,
     spawn_link(fn ->
       :global_group.monitor_nodes(true)
       Process.register(self(), __MODULE__)
       monitor()
     end)}
  end

  def monitor do
    receive do
      {:nodeup, node} ->
        X3m.System.Instrumenter.execute(:node_joined, %{}, %{node: node})

      {:nodedown, node} ->
        X3m.System.Instrumenter.execute(:node_left, %{}, %{node: node})
    end

    monitor()
  end
end
