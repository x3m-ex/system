defmodule X3m.System.GenAggregateMod do
  @moduledoc !"""
             Internal. Behaviour implemented by `X3m.System.GenAggregate`, letting message
             handlers talk to the aggregate process through a swappable contract.
             """
  @callback apply_event_stream(aggregate :: pid(), event_stream :: Enumerable.t()) :: :ok
  @callback handle_msg(
              aggregate :: pid(),
              cmd :: atom(),
              message :: X3m.System.Message.t(),
              opts :: Keyword.t()
            ) ::
              {:block, message :: X3m.System.Message.t(), transaction_id :: String.t()}
              | {:noblock, message :: X3m.System.Message.t(),
                 aggregate_state :: X3m.System.Aggregate.State.t()}
  @callback commit(
              aggregate :: pid(),
              transaction_id :: String.t(),
              message :: X3m.System.Message.t(),
              last_version :: integer()
            ) :: {:ok, aggregate_state :: X3m.System.Aggregate.State.t()} | :transaction_timeout
  @callback set_state(aggregate :: pid(), loaded_state :: term(), version :: integer()) :: :ok
end
