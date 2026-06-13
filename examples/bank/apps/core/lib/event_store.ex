defmodule Banking.Core.EventStore do
  @moduledoc !"""
             Extreme TCP connection to EventStore for the core aggregate app.
             """
  use Extreme, otp_app: :banking_core
end
