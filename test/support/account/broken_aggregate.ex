defmodule X3m.System.Test.Account.BrokenAggregate do
  @moduledoc "Aggregate whose `initial_state/0` raises, so its process never starts."
  use X3m.System.Aggregate
  alias X3m.System.Message, as: SysMsg

  @impl X3m.System.Aggregate
  def initial_state, do: raise("initial state unavailable")

  handle_msg :open_account, fn %SysMsg{} = msg, state ->
    {:block, SysMsg.created(msg, msg.aggregate_meta.id), state}
  end
end
