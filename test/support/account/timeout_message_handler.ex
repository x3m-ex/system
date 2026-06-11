defmodule X3m.System.Test.Account.TimeoutMessageHandler do
  @moduledoc false
  use X3m.System.MessageHandler,
    aggregate_mod: X3m.System.Test.Account.Aggregate,
    aggregate_repo: X3m.System.Test.Account.EventStore,
    stream: "timeout-accounts",
    pid_facade_mod: X3m.System.AggregatePidFacade,
    event_metadata: %{app_version: "test"}

  on_new_aggregate :open_account, commit_timeout: 50
  on_aggregate :deposit, commit_timeout: 50
end
