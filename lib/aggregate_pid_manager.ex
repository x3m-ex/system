defmodule X3m.System.AggregatePidManager do
  use Supervisor
  alias X3m.System.AggregateRegistry, as: Registry
  alias X3m.System.AggregateSup

  def start_link(prefix, aggregate_mod),
    do: Supervisor.start_link(__MODULE__, {prefix, aggregate_mod}, name: name(aggregate_mod))

  def init({prefix, aggregate_mod}) do
    children = [
      worker(Registry, [Registry.name(aggregate_mod)]),
      supervisor(AggregateSup, [prefix, aggregate_mod])
    ]

    supervise(children, strategy: :one_for_all)
  end

  def name(aggregate_mod),
    do: Module.concat(aggregate_mod, PidManager)
end
