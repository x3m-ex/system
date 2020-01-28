defmodule X3m.System.AggregateSup do
  use DynamicSupervisor

  def name(aggregate_mod),
    do: Module.concat(aggregate_mod, Sup)

  def start_link([_prefix, aggregate_mod]),
    do: DynamicSupervisor.start_link(__MODULE__, aggregate_mod, name: name(aggregate_mod))

  def start_child(sup_name, child_params \\ []) do
    spec = {X3m.System.GenAggregate, child_params}
    DynamicSupervisor.start_child(sup_name, spec)
  end

  def terminate_child(sup_name, pid),
    do: DynamicSupervisor.terminate_child(sup_name, pid)

  @impl DynamicSupervisor
  def init(aggregate_mod) do
    DynamicSupervisor.init(
      strategy: :one_for_one,
      extra_arguments: [aggregate_mod]
    )
  end
end
