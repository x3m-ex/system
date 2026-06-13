defmodule Banking.Core.Aggregates.Account.Commands.Deposit do
  @moduledoc !"""
             Validates the deposit command. Rejects if account is closed.
             """
  use Ecto.Schema
  import Ecto.Changeset
  alias X3m.System.Message, as: SysMsg
  alias Banking.Core.Aggregates.Account.{CommandHelpers, State}

  @primary_key false
  embedded_schema do
    field :id, :string
    field :amount, :integer
  end

  @spec new(msg :: SysMsg.t(), state :: State.t()) :: SysMsg.t()
  def new(%SysMsg{} = msg, %State{} = state) do
    %__MODULE__{}
    |> cast(msg.raw_request, [:id, :amount])
    |> validate_required([:id, :amount])
    |> validate_number(:amount, greater_than: 0)
    |> _reject_if_closed(state)
    |> CommandHelpers.put_request(msg)
  end

  defp _reject_if_closed(changeset, %State{closed?: true}),
    do: add_error(changeset, :id, "account is closed")

  defp _reject_if_closed(changeset, %State{}),
    do: changeset
end
