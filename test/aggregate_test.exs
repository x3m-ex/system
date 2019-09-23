defmodule X3m.System.AggregateTest do
  use ExUnit.Case, async: true

  alias X3m.System.Aggregate
  alias X3m.System.Aggregate.State
  alias X3m.System.Message, as: SysMsg

  defmodule TestAggregate do
    use Aggregate
    alias X3m.System.Message, as: SysMsg

    defmodule State, do: defstruct(~w(id name)a)

    def initial_state, do: %State{name: :test}

    handle_msg :no_block_example, &_no_block_example/2

    defp _no_block_example(%SysMsg{} = msg, %State{} = state) do
      {:noblock, msg, state}
    end
  end

  describe "initial_state/1" do
    test "returns nested state tructs" do
      assert %State{
               version: -1,
               client_state: %TestAggregate.State{
                 id: nil,
                 name: :test
               }
             } = Aggregate.initial_state(TestAggregate)
    end
  end

  describe "handle_msg/2 macro" do
    test "creates function" do
      msg = SysMsg.new(:whatever)
      state = Aggregate.initial_state(TestAggregate)

      assert {:noblock, ^msg, ^state} = TestAggregate.no_block_example(msg, state)
    end
  end
end
