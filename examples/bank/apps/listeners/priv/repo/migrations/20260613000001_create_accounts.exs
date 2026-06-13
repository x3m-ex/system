defmodule Banking.Listeners.Repo.Migrations.CreateAccounts do
  use Ecto.Migration

  def change do
    create table(:accounts, primary_key: false) do
      add :id, :string, primary_key: true
      add :owner_id, :string, null: false
      add :balance, :integer, null: false, default: 0
      add :status, :string, null: false, default: "open"

      timestamps()
    end

    create table(:events_catchup) do
      add :module_name, :string, null: false
      add :stream, :string, null: false
      add :ver, :integer, null: false, default: -1
    end

    create unique_index(:events_catchup, [:module_name, :stream])
  end
end
