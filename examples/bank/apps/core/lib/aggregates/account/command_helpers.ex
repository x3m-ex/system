defmodule Banking.Core.Aggregates.Account.CommandHelpers do
  @moduledoc !"""
             Shared helper for converting Ecto changesets into message requests.
             """
  alias X3m.System.Message, as: SysMsg

  @spec put_request(changeset :: Ecto.Changeset.t(), msg :: SysMsg.t()) :: SysMsg.t()
  def put_request(%Ecto.Changeset{valid?: false} = changeset, %SysMsg{} = msg),
    do: SysMsg.put_request(changeset, msg)

  def put_request(%Ecto.Changeset{valid?: true} = changeset, %SysMsg{} = msg) do
    changeset
    |> Ecto.Changeset.apply_changes()
    |> SysMsg.put_request(msg)
  end
end
