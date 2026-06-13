defmodule Banking.Core.LocalAggregates do
  @moduledoc !"""
             Registers aggregate supervision trees for this node.
             """
  use X3m.System.LocalAggregates, [
    Banking.Core.Aggregates.Account.Aggregate
  ]
end
