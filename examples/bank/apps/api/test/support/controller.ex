defmodule Banking.Api.Test.Controller do
  @moduledoc "Replies with the response a test put in the request."
  alias X3m.System.Message, as: SysMsg

  @spec respond_with(SysMsg.t()) :: {:reply, SysMsg.t()}
  def respond_with(%SysMsg{raw_request: %{"response" => response}} = msg),
    do: {:reply, SysMsg.return(msg, response)}
end
