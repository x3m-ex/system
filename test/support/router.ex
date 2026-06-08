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
end

defmodule X3m.System.Test.Router do
  use X3m.System.Router

  alias X3m.System.Test.Controller
  alias X3m.System.Message, as: SysMsg

  service :first, Controller
  service :unauthorized_service, Controller, :first
  service :custom_unauthorized_service, Controller, :first
  service :try_another_node, Controller

  servicep :private_service, Controller, :private

  def authorize(%SysMsg{service_name: :first}), do: :ok
  def authorize(%SysMsg{service_name: :private_service}), do: :ok
  def authorize(%SysMsg{service_name: :try_another_node}), do: :ok

  def authorize(%SysMsg{service_name: :custom_unauthorized_service}),
    do: {:forbidden, "None shall pass!"}
end
