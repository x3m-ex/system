defmodule X3m.System.ServiceRegistry.Implementation do
  @moduledoc false
  alias X3m.System.ServiceRegistry.State

  @spec register_remote_services({node, [{atom, atom}]}, State.t()) :: {:ok, State.t()}
  def register_remote_services(
        {node, services},
        %State{services: %State.Services{remote: remote_services}} = state
      ) do
    services = %State.Services{
      state.services
      | remote: _register_remote_services(remote_services, services, node)
    }

    {:ok, %{state | services: services}}
  end

  @spec remove_remote_services(State.Services.remote_services(), node) ::
          State.Services.remote_services()
  def remove_remote_services(services, node) do
    services
    |> Enum.map(fn {service, nodes} ->
      nodes =
        nodes
        |> Enum.reject(fn
          {^node, _} -> true
          _ -> false
        end)
        |> Enum.into(%{})

      {service, nodes}
    end)
    |> Enum.reject(fn
      {_, %{} = map} when map_size(map) == 0 -> true
      _ -> false
    end)
    |> Enum.into(%{})
  end

  @spec _register_remote_services(State.Services.remote_services(), [{atom, atom}], node) ::
          State.Services.remote_services()
  defp _register_remote_services(existing_services, new_services, node) do
    new_services
    |> Enum.reduce(existing_services, fn {new_service, mod}, acc ->
      acc
      |> Map.put_new(new_service, %{})
      |> put_in([new_service, node], mod)
    end)
  end
end
