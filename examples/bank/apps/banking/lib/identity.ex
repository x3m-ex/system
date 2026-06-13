defmodule Banking.Identity do
  @moduledoc """
  Represents the caller's identity, passed through message assigns.
  """

  @type t() :: %__MODULE__{
          user_id: String.t() | nil,
          admin?: boolean()
        }

  defstruct [:user_id, admin?: false]
end
