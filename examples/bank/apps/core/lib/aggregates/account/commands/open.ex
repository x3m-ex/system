defmodule Banking.Core.Aggregates.Account.Commands.Open do
  @moduledoc !"""
             Validates the open_account command.
             """
  use Ecto.Schema
  import Ecto.Changeset
  alias X3m.System.Message, as: SysMsg
  alias Banking.Core.Aggregates.Account.CommandHelpers

  @primary_key false
  embedded_schema do
    field :id, :string
    field :owner_id, :string
  end

  @spec new(msg :: SysMsg.t(), state :: term()) :: SysMsg.t()
  def new(%SysMsg{} = msg, _state) do
    %__MODULE__{}
    |> cast(msg.raw_request, [:id, :owner_id])
    |> validate_required([:id, :owner_id])
    |> CommandHelpers.put_request(msg)
  end
end
