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
end

defmodule X3m.System.Test.Router do
  use X3m.System.Router

  alias X3m.System.Test.Controller

  service :first, Controller

  servicep(:private_service, Controller, :private)
end
