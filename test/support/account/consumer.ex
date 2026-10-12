defmodule X3m.System.Test.Account.Consumer do
  @moduledoc """
  Calls a generated aggregate command the way a consumer would, so dialyzer checks the
  `X3m.System.Aggregate.State` contract from outside the library.
  """
  alias X3m.System.Aggregate
  alias X3m.System.Message, as: SysMsg
  alias X3m.System.Test.Account

  @doc "Opens an account on a fresh aggregate state."
  @spec open_account(message :: SysMsg.t()) ::
          {:block | :noblock, SysMsg.t(), Aggregate.State.t()}
  def open_account(%SysMsg{} = message) do
    initial_state = Aggregate.initial_state(Account.Aggregate)
    Account.Aggregate.open_account(message, initial_state)
  end
end
