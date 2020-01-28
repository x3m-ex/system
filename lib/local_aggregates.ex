defmodule X3m.System.LocalAggregates do
  defmacro __using__(opts) do
    quote do
      @moduledoc false

      use Supervisor
      require Logger

      def start_link(prefix),
        do:
          Supervisor.start_link(__MODULE__, prefix, name: X3m.System.LocalAggregates.name(prefix))

      def init(prefix) do
        children =
          unquote(opts)
          |> Enum.map(fn item -> aggregate_group(item, prefix) end)

        Supervisor.init(children, strategy: :one_for_one)
      end

      defp aggregate_group(aggr_mod, prefix) do
        name = X3m.System.AggregateGroup.name(aggr_mod)

        %{
          id: name,
          start: {X3m.System.AggregateGroup, :start_link, [prefix, aggr_mod]}
        }
      end
    end
  end

  def name(prefix),
    do: Module.concat(prefix, LocalAggregates)
end
