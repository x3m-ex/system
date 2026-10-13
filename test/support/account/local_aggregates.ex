defmodule X3m.System.Test.Account.LocalAggregates do
  @moduledoc false
  use X3m.System.LocalAggregates, [
    X3m.System.Test.Account.Aggregate,
    X3m.System.Test.Account.BrokenAggregate
  ]
end
