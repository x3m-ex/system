defmodule X3m.System.AggregateSup do
  use Supervisor

  def name(aggregate_mod),
    do: Module.concat(aggregate_mod, Sup)

  def start_link(prefix, aggregate_mod),
    do: Supervisor.start_link(__MODULE__, {prefix, aggregate_mod}, name: name(aggregate_mod))

  def start_child(sup_name, child_params \\ []),
    do: Supervisor.start_child(sup_name, child_params)

  def terminate_child(sup_name, pid),
    do: Supervisor.terminate_child(sup_name, pid)

  def init({_, aggregate_mod}) do
    children = [worker(X3m.System.GenAggregate, [aggregate_mod], restart: :temporary)]
    supervise(children, strategy: :simple_one_for_one)
  end
end
