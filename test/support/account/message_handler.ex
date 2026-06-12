defmodule X3m.System.Test.Account.MessageHandler do
  @moduledoc false
  use X3m.System.MessageHandler,
    aggregate_mod: X3m.System.Test.Account.Aggregate,
    aggregate_repo: X3m.System.Test.Account.EventStore,
    stream: "accounts",
    pid_facade_mod: X3m.System.AggregatePidFacade,
    event_metadata: %{app_version: "test"}

  on_new_aggregate :open_account
  on_aggregate :deposit
  on_aggregate :withdraw
  on_aggregate :close_account
  on_maybe_new_aggregate :ensure_account
end
