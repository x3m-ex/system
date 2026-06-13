defmodule Banking.Listeners.Repo do
  @moduledoc !"""
             Ecto repository for the denormalized read model.
             """
  use Ecto.Repo,
    otp_app: :banking_listeners,
    adapter: Ecto.Adapters.Postgres
end
