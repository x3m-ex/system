defmodule X3m.System.LocalAggregatesSupervision do
  use Supervisor

  def start_link([configuration_module, prefix]),
    do: Supervisor.start_link(__MODULE__, {configuration_module, prefix}, name: name(prefix))

  def init({configuration_module, prefix}) do
    children = [supervisor(configuration_module, [prefix])]
    supervise(children, strategy: :one_for_one)
  end

  defp name(prefix),
    do: Module.concat(prefix, LocalAggregateSupervision)
end
