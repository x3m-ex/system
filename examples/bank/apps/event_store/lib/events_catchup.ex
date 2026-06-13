defmodule Banking.EventStore.EventsCatchup do
  @moduledoc !"""
             Ecto schema for tracking listener catch-up position per stream.
             """
  use Ecto.Schema

  @type t() :: %__MODULE__{
          module_name: String.t(),
          stream: String.t(),
          ver: integer()
        }

  schema "events_catchup" do
    field :module_name, :string
    field :stream, :string
    field :ver, :integer
  end
end
