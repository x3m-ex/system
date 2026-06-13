defmodule Banking.EventStore.DB do
  @moduledoc !"""
             Catch-up tracking for event listeners.
             Stores the last acknowledged event number per listener module and stream.
             """
  import Ecto.Query
  alias Banking.EventStore.EventsCatchup

  @spec in_transaction(repo :: module(), fun :: (-> term())) :: :ok | X3m.System.Message.t()
  def in_transaction(repo, fun) do
    repo.transaction(fun)
    |> case do
      {:ok, %X3m.System.Message{} = msg} -> msg
      {:ok, _} -> :ok
    end
  end

  @spec ack_event(
          repo :: module(),
          module_name :: String.t(),
          stream :: String.t(),
          event_number :: integer()
        ) :: :ok
  def ack_event(repo, module_name, stream, event_number) do
    query =
      from(e in EventsCatchup,
        where: e.module_name == ^module_name and e.stream == ^stream
      )

    {1, _} = repo.update_all(query, set: [ver: event_number])
    :ok
  end

  @spec get_last_event(repo :: module(), module_name :: String.t(), stream :: String.t()) ::
          integer()
  def get_last_event(repo, module_name, stream) do
    query =
      from(e in EventsCatchup,
        where: e.module_name == ^module_name and e.stream == ^stream
      )

    repo
    |> apply(:one, [query])
    |> case do
      nil ->
        repo.insert(%EventsCatchup{module_name: module_name, stream: stream, ver: -1})
        -1

      rec ->
        rec.ver
    end
  end
end
