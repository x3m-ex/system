defmodule X3m.System.Test.Account.UnloadOnStateHandler do
  @moduledoc false
  alias X3m.System.Test.Account.State

  use X3m.System.MessageHandler,
    aggregate_mod: X3m.System.Test.Account.Aggregate,
    aggregate_repo: X3m.System.Test.Account.EventStore,
    stream: "unload-state-accounts",
    pid_facade_mod: X3m.System.AggregatePidFacade,
    event_metadata: %{app_version: "test"},
    unload_aggregate_on: %{state: &__MODULE__.unload_on_state/1}

  on_new_aggregate :open_account
  on_aggregate :deposit
  on_aggregate :close_account

  def unload_on_state(%State{closed?: true}), do: :unload
  def unload_on_state(%State{balance: balance}) when balance > 1_000, do: {:in, 30}
  def unload_on_state(%State{}), do: :skip
end
