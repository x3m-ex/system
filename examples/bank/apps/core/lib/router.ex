defmodule Banking.Core.Router do
  @moduledoc !"""
             Registers command services and routes messages to the account message handler.
             """
  use X3m.System.Router
  alias Banking.Core.MessageHandler, as: Account

  service :open_account, Account
  service :deposit, Account
  service :withdraw, Account
  service :close_account, Account

  def authorize(%X3m.System.Message{}), do: :ok
end
