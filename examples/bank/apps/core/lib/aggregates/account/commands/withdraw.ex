defmodule Banking.Core.Aggregates.Account.Commands.Withdraw do
  @moduledoc !"""
             Validates the withdraw command. Rejects if account is closed.
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
    |> _reject_if_insufficient(state)
    |> CommandHelpers.put_request(msg)
  end

  defp _reject_if_closed(changeset, %State{closed?: true}),
    do: add_error(changeset, :id, "account is closed")

  defp _reject_if_closed(changeset, %State{}),
    do: changeset

  defp _reject_if_insufficient(%Ecto.Changeset{valid?: false} = changeset, _state),
    do: changeset

  defp _reject_if_insufficient(changeset, %State{balance: balance}) do
    amount = get_change(changeset, :amount, 0)

    if amount > balance,
      do: add_error(changeset, :amount, "insufficient funds"),
      else: changeset
  end
end
