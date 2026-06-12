defmodule X3m.System.Test.Controller do
  alias X3m.System.Message

  def first(%Message{} = msg) do
    msg = Message.ok(msg, :from_first)
    {:reply, msg}
  end

  def private(%Message{} = msg) do
    msg = Message.ok(msg, :from_private)
    {:reply, msg}
  end

  def try_another_node(%Message{} = msg) do
    msg = Message.error(msg, {:try_another_node, :quorum_not_met})
    {:reply, msg}
  end

  # Rejects or responds based on the *node-local* `:reject_quorum?` app env, so each
  # peer in a cluster can be told independently whether to ask for another node.
  def maybe_another_node(%Message{} = msg) do
    if Application.get_env(:x3m_system, :reject_quorum?, false),
      do: {:reply, Message.error(msg, {:try_another_node, :quorum_not_met})},
      else: {:reply, Message.ok(msg, :from_quorum)}
  end
end
