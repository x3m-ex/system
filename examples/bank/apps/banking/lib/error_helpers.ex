defmodule Banking.ErrorHelpers do
  @moduledoc !"""
  Converts Ecto changesets into JSON-friendly error maps.
  """

  @spec traverse_errors(changeset :: Ecto.Changeset.t()) :: %{atom() => [String.t()]}
  def traverse_errors(%Ecto.Changeset{} = changeset) do
    Ecto.Changeset.traverse_errors(changeset, fn {msg, _opts} -> msg end)
  end
end
