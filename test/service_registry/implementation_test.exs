defmodule X3m.System.ServiceRegistry.ImplementationTest do
  use ExUnit.Case, async: true
  alias X3m.System.ServiceRegistry.Implementation, as: Impl
  alias X3m.System.ServiceRegistry.State

  describe "register_remote_services/2" do
    test "adds new services in empty map" do
      services = [svc1: Mod1, svc2: Mod1]
      state = %State{services: %State.Services{local: %{a: :b}, remote: %{}}}

      assert {:ok,
              %State{
                services: %State.Services{
                  remote: %{
                    svc1: %{node1: Mod1},
                    svc2: %{node1: Mod1}
                  },
                  local: %{
                    a: :b
                  }
                }
              }} = Impl.register_remote_services({:node1, services}, state)
    end

    test "removes existing services for given node, but leaves services from other nodes" do
      services = [svc1: Mod1, svc2: Mod1]

      state = %State{
        services: %State.Services{
          remote: %{
            svc1: %{node1: Mod1},
            svc3: %{node2: Mod2}
          },
          local: %{a: :b}
        }
      }

      assert {:ok,
              %State{
                services: %State.Services{
                  remote: %{
                    svc1: %{node1: Mod1},
                    svc2: %{node1: Mod1},
                    svc3: %{node2: Mod2}
                  },
                  local: %{
                    a: :b
                  }
                }
              }} = Impl.register_remote_services({:node1, services}, state)
    end
  end
end
