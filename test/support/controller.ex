defmodule X3m.System.Test.Controller do
  alias X3m.System.Message

  def first(%Message{} = msg) do
    msg = Message.ok(msg, :from_first)
    {:reply, msg}
  end

  def slow(%Message{raw_request: %{sleep_ms: sleep_ms} = raw_request} = msg) do
    _report_handler(raw_request)
    Process.sleep(sleep_ms)
    {:reply, Message.ok(msg, :from_slow)}
  end

  def raising(%Message{}), do: raise("handler failed")

  def throwing(%Message{}), do: throw(:handler_threw)

  def exiting(%Message{}), do: exit(:handler_exited)

  # replies from another process after the handler itself has returned
  def delegated(%Message{raw_request: %{reply_after_ms: reply_after_ms}} = msg) do
    spawn(fn ->
      Process.sleep(reply_after_ms)
      send(msg.reply_to, Message.ok(msg, :from_delegate))
    end)

    :noreply
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

  defp _report_handler(%{test_pid: test_pid}), do: send(test_pid, {:handler, self()})
  defp _report_handler(%{}), do: :ok
end
