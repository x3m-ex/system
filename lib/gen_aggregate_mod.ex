defmodule X3m.System.GenAggregateMod do
  @callback apply_event_stream(pid, function) :: :ok
  @callback handle_msg(pid, atom, X3m.System.Message.t()) ::
              {:ok, X3m.System.Message.t(), any} | any
  @callback commit(pid, String.t(), X3m.System.Message.t(), integer) ::
              {:ok, X3m.System.Aggregate.State.t()} | :transaction_timeout
end
