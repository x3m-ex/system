defmodule X3m.System.LocalAggregatesSupervision do
  @moduledoc """
  Supervises the aggregate processes that run on the local node.

  Add it to your application's supervision tree, pointing it at your
  `X3m.System.LocalAggregates` configuration module and an app prefix:

      {X3m.System.LocalAggregatesSupervision, [MyApp.LocalAggregates, MyApp]}

  See the "Aggregates & Event Sourcing" guide for the full setup.
  """
  use Supervisor

  def start_link([configuration_module, prefix]),
    do: Supervisor.start_link(__MODULE__, {configuration_module, prefix}, name: name(prefix))

  @impl Supervisor
  def init({configuration_module, prefix}) do
    children = [{configuration_module, prefix}]
    Supervisor.init(children, strategy: :one_for_one)
  end

  defp name(prefix),
    do: Module.concat(prefix, LocalAggregateSupervision)
end
