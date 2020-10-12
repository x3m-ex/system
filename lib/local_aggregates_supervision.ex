defmodule X3m.System.LocalAggregatesSupervision do
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
