defmodule Banking.Core.Aggregates.Account.Events.Withdrawn do
  @moduledoc !"""
             Emitted when funds are withdrawn from an account.
             """
  defstruct [:id, :amount]
end
