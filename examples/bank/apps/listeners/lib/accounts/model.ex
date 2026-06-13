defmodule Banking.Listeners.Accounts.Model do
  @moduledoc !"""
             Ecto schema for the accounts read model table.
             """
  use Ecto.Schema

  @primary_key {:id, :string, autogenerate: false}

  schema "accounts" do
    field :owner_id, :string
    field :balance, :integer, default: 0
    field :status, :string, default: "open"

    timestamps()
  end
end
