defmodule Banking.Listeners.Services.ListAccounts do
  @moduledoc !"""
             Query service — returns all accounts from the read model.
             """
  alias Banking.Listeners.Repo
  alias Banking.Listeners.Accounts.Model
  alias X3m.System.Message, as: SysMsg

  @spec handle(msg :: SysMsg.t()) :: {:reply, SysMsg.t()}
  def handle(%SysMsg{} = msg) do
    accounts =
      Model
      |> Repo.all()
      |> Enum.map(&_to_map/1)

    {:reply, SysMsg.return(msg, {:ok, accounts})}
  end

  defp _to_map(%Model{} = account) do
    %{
      id: account.id,
      owner_id: account.owner_id,
      balance: account.balance,
      status: account.status
    }
  end
end
