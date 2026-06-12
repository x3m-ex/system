defmodule X3m.System.Test.Account.UnloadOnEventsHandler do
  @moduledoc false
  use X3m.System.MessageHandler,
    aggregate_mod: X3m.System.Test.Account.Aggregate,
    aggregate_repo: X3m.System.Test.Account.EventStore,
    stream: "unload-evt-accounts",
    pid_facade_mod: X3m.System.AggregatePidFacade,
    event_metadata: %{app_version: "test"},
    unload_aggregate_on: %{events: %{X3m.System.Test.Account.Events.Deposited => {:in, 30}}}

  on_new_aggregate :open_account
  on_aggregate :deposit
end
