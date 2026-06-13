defmodule Banking.Core.AggregateRepo do
  @moduledoc !"""
             Aggregate event persistence via EventStore.
             """
  use Banking.EventStore.AggregateRepo,
    extreme: Banking.Core.EventStore
end
