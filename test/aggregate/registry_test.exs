defmodule X3m.System.AggregateRegistryTest do
  use ExUnit.Case, async: false

  alias X3m.System.AggregateRegistry, as: Registry

  setup do
    name = Module.concat(__MODULE__, :"R#{System.unique_integer([:positive])}")
    start_supervised!(%{id: name, start: {Registry, :start_link, [name]}})
    %{registry: name}
  end

  test "register then get returns the pid; has_key? is true", %{registry: reg} do
    pid = spawn(fn -> Process.sleep(:infinity) end)

    assert :ok == Registry.register(reg, "k1", pid)
    assert {:ok, ^pid} = Registry.get(reg, "k1")
    assert Registry.has_key?(reg, "k1") == true
    assert Registry.has_key?(reg, "missing") == false
  end

  test "registering an already-registered key returns an error", %{registry: reg} do
    pid = spawn(fn -> Process.sleep(:infinity) end)

    assert :ok == Registry.register(reg, "dup", pid)
    assert {:error, :key_already_registered, ^pid} = Registry.register(reg, "dup", pid)
  end

  test "entry is removed when the registered process goes down", %{registry: reg} do
    pid = spawn(fn -> Process.sleep(:infinity) end)

    assert :ok == Registry.register(reg, "k2", pid)
    Process.exit(pid, :kill)
    Process.sleep(50)

    assert :error == Registry.get(reg, "k2")
    assert Registry.has_key?(reg, "k2") == false
  end
end
