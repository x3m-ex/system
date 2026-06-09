defmodule X3m.System.Test.Account.State do
  @moduledoc false
  defstruct id: nil, owner_id: nil, balance: 0, closed?: false, highest_rejected_withdrawal: 0
end
