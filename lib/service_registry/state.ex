defmodule X3m.System.ServiceRegistry.State do
  @moduledoc !"""
             Internal. State struct for `X3m.System.ServiceRegistry`, holding the local,
             public and remote service maps.
             """
  defmodule Services do
    @moduledoc !"Internal. Local/public/remote service maps held by the service registry."
    @type t() :: %__MODULE__{local: local_services(), remote: remote_services()}
    @type local_services() :: %{service_name() => node()}
    @type remote_services() :: %{service_name() => %{node() => module :: atom()}}
    @type service_name() :: atom()

    @enforce_keys ~w(local public remote)a
    defstruct @enforce_keys
  end

  @type t() :: %__MODULE__{services: Services.t()}

  @enforce_keys ~w(services)a
  defstruct @enforce_keys
end
