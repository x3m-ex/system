defmodule X3m.System.Test.Account.BrokenMessageHandler do
  @moduledoc "Message handler over `BrokenAggregate`, whose processes fail to start."
  use X3m.System.MessageHandler,
    aggregate_mod: X3m.System.Test.Account.BrokenAggregate,
    aggregate_repo: X3m.System.Test.Account.EventStore,
    stream: "broken-accounts",
    pid_facade_mod: X3m.System.AggregatePidFacade

  on_new_aggregate :open_account
  on_aggregate :deposit
end
