defmodule Banking.Api.Test.Router do
  @moduledoc "Test router whose `:respond_with` service replies with the requested response."
  use X3m.System.Router

  alias X3m.System.Message, as: SysMsg

  service :respond_with, Banking.Api.Test.Controller

  @spec authorize(SysMsg.t()) :: :ok
  def authorize(%SysMsg{}), do: :ok
end
