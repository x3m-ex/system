defmodule Banking.Listeners.Accounts.Listener do
  @moduledoc !"""
             Subscribes to the accounts category stream and dispatches events to denormalizers.
             """
  use Banking.EventStore.Listener,
    stream: "$ce-accounts",
    db_repo: Banking.Listeners.Repo,
    module_name: "Banking.Listeners.Accounts.Listener"

  alias Banking.Core.Aggregates.Account.Events

  on_event(Events.Opened, dispatch: :account_opened!)
  on_event(Events.Deposited, dispatch: :account_deposited!)
  on_event(Events.Withdrawn, dispatch: :account_withdrawn!)
  on_event(Events.Closed, dispatch: :account_closed!)
end
