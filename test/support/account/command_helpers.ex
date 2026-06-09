defmodule X3m.System.Test.Account.CommandHelpers do
  @moduledoc false
  alias X3m.System.Message, as: SysMsg

  def put_request(%Ecto.Changeset{valid?: false} = changeset, %SysMsg{} = msg),
    do: SysMsg.put_request(changeset, msg)

  def put_request(%Ecto.Changeset{valid?: true} = changeset, %SysMsg{} = msg) do
    changeset
    |> Ecto.Changeset.apply_changes()
    |> SysMsg.put_request(msg)
  end
end
