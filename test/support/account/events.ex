defmodule X3m.System.Test.Account.Events do
  @moduledoc false
  defmodule Opened, do: defstruct([:id, :owner_id])
  defmodule OwnerChanged, do: defstruct([:id, :owner_id])
  defmodule Deposited, do: defstruct([:id, :amount])
  defmodule Withdrawn, do: defstruct([:id, :amount])
  defmodule WithdrawalRejected, do: defstruct([:id, :amount, :balance])
  defmodule Closed, do: defstruct([:id])
end
