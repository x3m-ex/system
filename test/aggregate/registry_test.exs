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

    assert :ok == _await_removal(reg, "k2", 1_000)
    assert Registry.has_key?(reg, "k2") == false
  end

  for reason <- [:normal, :shutdown, {:shutdown, :unloaded}] do
    test "an intentional #{inspect(reason)} exit is logged at debug, not warning", %{
      registry: reg
    } do
      key = "intentional-#{System.unique_integer([:positive])}"
      pid = _exit_on_request()
      :ok = Registry.register(reg, key, pid)

      log =
        ExUnit.CaptureLog.capture_log(fn ->
          send(pid, {:exit, unquote(Macro.escape(reason))})
          assert :ok == _await_removal(reg, key, 1_000)
        end)

      assert log =~
               "[debug] Process #{inspect(pid)} went down: #{inspect(unquote(Macro.escape(reason)))}"

      refute log =~ "[warning]"
    end
  end

  test "an unexpected exit is logged as a warning", %{registry: reg} do
    key = "unexpected-#{System.unique_integer([:positive])}"
    pid = _exit_on_request()
    :ok = Registry.register(reg, key, pid)

    log =
      ExUnit.CaptureLog.capture_log(fn ->
        Process.exit(pid, :kill)
        assert :ok == _await_removal(reg, key, 1_000)
      end)

    assert log =~ "[warning] Process #{inspect(pid)} went down: :killed"
  end

  test "a DOWN for a ref it does not know leaves the registry running", %{registry: reg} do
    registry_pid = Process.whereis(reg)
    ref = Process.monitor(registry_pid)

    send(registry_pid, {:DOWN, make_ref(), :process, self(), :normal})

    assert false == Registry.has_key?(reg, "any")
    refute_received {:DOWN, ^ref, :process, ^registry_pid, _reason}
  end

  test "unregister drops the key at once and the process going down later is not logged", %{
    registry: reg
  } do
    key = "unregistered-#{System.unique_integer([:positive])}"
    pid = _exit_on_request()
    :ok = Registry.register(reg, key, pid)

    assert :ok == Registry.unregister(reg, key)
    assert :error == Registry.get(reg, key)

    log =
      ExUnit.CaptureLog.capture_log(fn ->
        down_ref = Process.monitor(pid)
        send(pid, {:exit, :killed_later})
        assert_receive {:DOWN, ^down_ref, :process, ^pid, :killed_later}
        assert false == Registry.has_key?(reg, key)
      end)

    refute log =~ "went down"
  end

  test "unregistering one key leaves other keys and their monitors intact", %{registry: reg} do
    dropped = _exit_on_request()
    kept = _exit_on_request()
    :ok = Registry.register(reg, "dropped", dropped)
    :ok = Registry.register(reg, "kept", kept)

    assert :ok == Registry.unregister(reg, "dropped")
    assert {:ok, ^kept} = Registry.get(reg, "kept")

    send(kept, {:exit, :normal})
    assert :ok == _await_removal(reg, "kept", 1_000)
  end

  test "unregistering an unknown key is a no-op", %{registry: reg} do
    assert :ok == Registry.unregister(reg, "never-registered")
  end

  defp _exit_on_request() do
    spawn(fn ->
      receive do
        {:exit, reason} -> exit(reason)
      end
    end)
  end

  # the registry drops the entry when it handles the DOWN, asynchronously to this process
  defp _await_removal(reg, key, deadline_ms) do
    case {Registry.get(reg, key), deadline_ms} do
      {:error, _deadline_ms} ->
        :ok

      {{:ok, _pid}, deadline_ms} when deadline_ms > 0 ->
        Process.sleep(10)
        _await_removal(reg, key, deadline_ms - 10)

      {{:ok, pid}, _deadline_ms} ->
        {:still_registered, pid}
    end
  end
end
