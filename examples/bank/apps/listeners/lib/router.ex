defmodule Banking.Listeners.Router do
  @moduledoc !"""
             Registers denormalization and read services.
             """
  use X3m.System.Router
  alias Banking.Listeners.Accounts.Denormalizer
  alias Banking.Listeners.Services

  # Read services (dispatched by API)
  service :get_account, Services.GetAccount, :handle
  service :list_accounts, Services.ListAccounts, :handle

  # Denormalization services (dispatched by listener)
  servicep :account_opened!, Denormalizer, :denormalize
  servicep :account_deposited!, Denormalizer, :denormalize
  servicep :account_withdrawn!, Denormalizer, :denormalize
  servicep :account_closed!, Denormalizer, :denormalize

  def authorize(%X3m.System.Message{service_name: :list_accounts, assigns: assigns}) do
    if assigns[:invoked_by] && assigns.invoked_by.admin?,
      do: :ok,
      else: :forbidden
  end

  def authorize(%X3m.System.Message{}), do: :ok
end
