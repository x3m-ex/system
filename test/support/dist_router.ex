defmodule X3m.System.Test.DistRouter do
  @moduledoc !"""
             Router used only by the distributed tests. It is intentionally NOT registered in
             `test_helper.exs`, so the manager node never hosts these services. Each peer that should
             host them calls `register_services/0` (via rpc), keeping the set of providers a client
             node discovers limited to exactly the peers under test.
             """

  use X3m.System.Router

  alias X3m.System.Test.Controller

  service :remote_first, Controller, :first
  service :maybe_another_node, Controller

  def authorize(_), do: :ok
end
