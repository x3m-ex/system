defmodule X3m.System.Test.Account.Commands.Open do
  @moduledoc false
  use Ecto.Schema
  import Ecto.Changeset
  alias X3m.System.Message, as: SysMsg
  alias X3m.System.Test.Account.CommandHelpers

  @primary_key false
  embedded_schema do
    field :id, :string
    field :owner_id, :string
  end

  def new(%SysMsg{} = msg, _state) do
    %__MODULE__{}
    |> cast(msg.raw_request, [:id, :owner_id])
    |> validate_required([:id, :owner_id])
    |> CommandHelpers.put_request(msg)
  end
end
