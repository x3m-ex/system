defmodule Banking.Core.Aggregates.Account.Events.Deposited do
  @moduledoc !"""
             Emitted when funds are deposited into an account.
             """
  defstruct [:id, :amount]
end
