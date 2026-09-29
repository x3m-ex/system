defmodule X3m.System.Test.DistRouter do
  @moduledoc !"""
             Router used only by the distributed tests. It is intentionally NOT registered in
             `test_helper.exs`, so the manager node never hosts these services. Each peer that should
             host them calls `register_services/0` (via rpc), keeping the set of providers a client
             node discovers limited to exactly the peers under test.
             """

  use X3m.System.Router

  alias X3m.System.Message
  alias X3m.System.Test.Controller

  service :remote_first, Controller, :first
  service :maybe_another_node, Controller
  service :slow_remote, Controller, :slow
  service :raising_remote, Controller, :raising
  service :throwing_remote, Controller, :throwing
  service :exiting_remote, Controller, :exiting

  def authorize(%Message{raw_request: %{authorize_sleep_ms: sleep_ms}}) do
    Process.sleep(sleep_ms)
    :ok
  end

  # node-local, so each peer can be told independently to fail its checks
  def authorize(%Message{}) do
    if Application.get_env(:x3m_system, :fail_authorize?, false),
      do: raise("authorization failed"),
      else: :ok
  end
end
