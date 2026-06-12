defmodule X3m.System.GenAggregateMod do
  @moduledoc !"""
             Internal. Behaviour implemented by `X3m.System.GenAggregate`, letting message
             handlers talk to the aggregate process through a swappable contract.
             """
  @callback apply_event_stream(pid, function) :: :ok
  @callback handle_msg(pid, atom, X3m.System.Message.t(), Keyword.t()) ::
              {:ok, X3m.System.Message.t(), any} | any
  @callback commit(pid, String.t(), X3m.System.Message.t(), integer) ::
              {:ok, X3m.System.Aggregate.State.t()} | :transaction_timeout
  @callback set_state(pid, loaded_state :: term(), version :: integer()) :: :ok
end
