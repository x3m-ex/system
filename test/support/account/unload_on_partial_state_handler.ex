defmodule X3m.System.Test.Account.UnloadOnPartialStateHandler do
  @moduledoc false
  alias X3m.System.Test.Account.State

  use X3m.System.MessageHandler,
    aggregate_mod: X3m.System.Test.Account.Aggregate,
    aggregate_repo: X3m.System.Test.Account.EventStore,
    stream: "unload-partial-accounts",
    pid_facade_mod: X3m.System.AggregatePidFacade,
    event_metadata: %{app_version: "test"},
    unload_aggregate_on: %{state: &__MODULE__.only_closed/1}

  on_new_aggregate :open_account
  on_aggregate :deposit

  # Intentionally no clause for a non-closed state -> FunctionClauseError -> rescued to :skip.
  def only_closed(%State{closed?: true}), do: :unload
end
