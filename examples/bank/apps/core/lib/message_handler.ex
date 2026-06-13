defmodule Banking.Core.MessageHandler do
  @moduledoc !"""
             Wires commands to the Account aggregate via x3m_system's MessageHandler macro.
             """
  use X3m.System.MessageHandler,
    aggregate_mod: Banking.Core.Aggregates.Account.Aggregate,
    aggregate_repo: Banking.Core.AggregateRepo,
    stream: "accounts",
    pid_facade_mod: X3m.System.AggregatePidFacade,
    event_metadata: %{app_version: "0.1.0"}

  on_new_aggregate :open_account
  on_aggregate :deposit
  on_aggregate :withdraw
  on_aggregate :close_account
end
