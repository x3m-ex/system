defmodule X3m.System.Test.Account.AbandoningLoadHandler do
  @moduledoc false
  # when_pid_is_not_registered/3 runs in the pid facade process
  use X3m.System.MessageHandler,
    aggregate_mod: X3m.System.Test.Account.Aggregate,
    aggregate_repo: X3m.System.Test.Account.EventStore,
    stream: "accounts",
    pid_facade_mod: X3m.System.AggregatePidFacade

  on_aggregate :deposit

  def when_pid_is_not_registered(_aggregate_mod, id, spawn_new_fun) do
    {:ok, _pid} = spawn_new_fun.()
    :ok = exit_process(id, :abandoned_load)
    {:error, :not_found}
  end
end
