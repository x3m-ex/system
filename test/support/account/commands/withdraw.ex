defmodule X3m.System.Test.Account.Commands.Withdraw do
  @moduledoc false
  use Ecto.Schema
  import Ecto.Changeset
  alias X3m.System.Message, as: SysMsg
  alias X3m.System.Test.Account.CommandHelpers

  @primary_key false
  embedded_schema do
    field :id, :string
    field :amount, :integer
  end

  def new(%SysMsg{} = msg, _state) do
    %__MODULE__{}
    |> cast(msg.raw_request, [:id, :amount])
    |> validate_required([:id, :amount])
    |> validate_number(:amount, greater_than: 0)
    |> CommandHelpers.put_request(msg)
  end
end
