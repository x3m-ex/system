defmodule X3m.System.Test.Account.ReactiveMessageHandler do
  @moduledoc false
  use X3m.System.MessageHandler,
    aggregate_mod: X3m.System.Test.Account.Aggregate,
    aggregate_repo: X3m.System.Test.Account.EventStore,
    stream: "reactive-accounts",
    pid_facade_mod: X3m.System.AggregatePidFacade,
    event_metadata: %{app_version: "test"}

  alias X3m.System.Message
  alias X3m.System.Test.Account.Events

  on_new_aggregate :open_account
  on_aggregate :withdraw

  # React: tell the registered test process what was produced.
  # Filter: never persist WithdrawalRejected (a transient fact); persist the rest.
  def save_events(%Message{} = message) do
    if pid = Process.whereis(:reactive_test_observer),
      do: send(pid, {:reacted, message.events})

    persistable = Enum.reject(message.events, &match?(%Events.WithdrawalRejected{}, &1))

    super(%{message | events: persistable})
  end
end
