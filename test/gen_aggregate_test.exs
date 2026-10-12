defmodule X3m.System.GenAggregateTest do
  use ExUnit.Case, async: true

  alias X3m.System.GenAggregate
  alias X3m.System.Message

  describe "commit/4" do
    test "returns at once when the aggregate is already dead" do
      pid = spawn(fn -> :ok end)
      ref = Process.monitor(pid)
      assert_receive {:DOWN, ^ref, :process, ^pid, _reason}

      {elapsed_us, result} = :timer.tc(fn -> _commit(pid, "t1") end)

      assert :transaction_timeout == result
      assert elapsed_us < 500_000
    end

    test "returns at once when the aggregate dies while the caller waits" do
      pid =
        spawn(fn ->
          receive do
            {:commit, _transaction_id, _message, _last_version, _from} -> exit(:boom)
          end
        end)

      {elapsed_us, result} = :timer.tc(fn -> _commit(pid, "t2") end)

      assert :transaction_timeout == result
      assert elapsed_us < 500_000
    end

    test "returns the committed state and leaves no monitor message behind" do
      pid =
        spawn(fn ->
          receive do
            {:commit, transaction_id, _message, _last_version, from} ->
              send(from, {:transaction_commited, transaction_id, :committed_state})
          end
        end)

      assert {:ok, :committed_state} == _commit(pid, "t3")
      refute_receive {:DOWN, _ref, :process, ^pid, _reason}, 50
    end

    test "gives up on a live aggregate that never replies and leaves no monitor behind" do
      pid = spawn(fn -> Process.sleep(:infinity) end)

      assert :transaction_timeout == _commit(pid, "t4")

      Process.exit(pid, :kill)
      refute_receive {:DOWN, _ref, :process, ^pid, _reason}, 50
    end
  end

  defp _commit(pid, transaction_id) do
    message = Message.new(:deposit)
    GenAggregate.commit(pid, transaction_id, message, 0)
  end
end
