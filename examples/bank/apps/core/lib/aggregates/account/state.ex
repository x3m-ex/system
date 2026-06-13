defmodule Banking.Core.Aggregates.Account.State do
  @moduledoc """
  Account aggregate state — rebuilt from the event stream.
  """

  @type t() :: %__MODULE__{
          id: String.t() | nil,
          owner_id: String.t() | nil,
          balance: non_neg_integer(),
          closed?: boolean()
        }

  defstruct [:id, :owner_id, balance: 0, closed?: false]
end
