defmodule Banking.Core.Aggregates.Account.Events.Opened do
  @moduledoc !"""
             Emitted when a new account is created.
             """
  defstruct [:id, :owner_id]
end
