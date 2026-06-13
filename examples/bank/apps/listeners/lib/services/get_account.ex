defmodule Banking.Listeners.Services.GetAccount do
  @moduledoc !"""
             Query service — returns a single account by ID from the read model.
             """
  alias Banking.Listeners.Repo
  alias Banking.Listeners.Accounts.Model
  alias X3m.System.Message, as: SysMsg

  @spec handle(msg :: SysMsg.t()) :: {:reply, SysMsg.t()}
  def handle(%SysMsg{raw_request: %{"id" => id}} = msg) do
    Repo.get(Model, id)
    |> case do
      nil ->
        {:reply, SysMsg.error(msg, :not_found)}

      %Model{} = account ->
        {:reply, SysMsg.return(msg, {:ok, _to_map(account)})}
    end
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
