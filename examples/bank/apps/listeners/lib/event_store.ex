defmodule Banking.Listeners.EventStore do
  @moduledoc !"""
             Extreme TCP connection to EventStore for the listeners app.
             """
  use Extreme, otp_app: :banking_listeners
end
