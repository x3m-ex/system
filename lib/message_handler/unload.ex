defmodule X3m.System.MessageHandler.Unload do
  @moduledoc !"""
             Internal. Decides whether and when an aggregate process is torn down after a
             command, from a message handler's `:unload_aggregate_on` rules (keyed on emitted
             events and/or current state).

             Extracted from the `X3m.System.MessageHandler` macro on purpose: here the rules
             are an ordinary `map()` argument, so the compiler does not narrow them to the
             empty-map literal a consumer without `:unload_aggregate_on` would otherwise inline
             (which trips the type checker on the optional `:events`/`:state` lookups).
             """

  alias X3m.System.Message

  @doc """
  Applies the `unload_aggregate_on` `rules` for a just-committed `message`.

  `rules` is the handler's `:unload_aggregate_on` map, with optional keys:

    * `:events` - `%{event_struct_module => {:in, milliseconds}}`; for each emitted event whose
      struct matches a key, a delayed `{:exit_process, pid, reason}` is sent to `pid_facade_name`.
    * `:state` - a 1-arity function of the new `client_state` returning `:skip`, `:unload` or
      `{:in, milliseconds}`.

  Schedules the event-based teardowns as a side effect and returns the state-based decision for
  the caller to act on (`:skip` keeps the process, `:unload` tears it down now, `{:in, ms}`
  after `ms`). A `FunctionClauseError` raised by the `:state` function is treated as `:skip`.
  """
  @spec decide(
          rules :: map(),
          message :: Message.t(),
          client_state :: term(),
          pid :: pid(),
          pid_facade_name :: atom()
        ) :: :skip | :unload | {:in, pos_integer()}
  def decide(rules, %Message{} = message, client_state, pid, pid_facade_name) do
    rules
    |> Map.get(:events, %{})
    |> Enum.each(fn {event, time} ->
      _schedule_on_events(message.events, event, time, pid, pid_facade_name)
    end)

    rules
    |> Map.get(:state)
    |> _decide_on_state(client_state)
  end

  defp _decide_on_state(fun, client_state) when is_function(fun) do
    fun.(client_state)
  rescue
    FunctionClauseError -> :skip
  end

  defp _decide_on_state(_state_rule, _client_state),
    do: :skip

  defp _schedule_on_events([], _event, _time, _pid, _pid_facade_name),
    do: :ok

  defp _schedule_on_events([%{__struct__: event} | rest], event, time, pid, pid_facade_name) do
    _create_scheduler(pid, time, event, pid_facade_name)
    _schedule_on_events(rest, event, time, pid, pid_facade_name)
  end

  defp _schedule_on_events([_other | rest], event, time, pid, pid_facade_name),
    do: _schedule_on_events(rest, event, time, pid, pid_facade_name)

  defp _create_scheduler(pid, {:in, milliseconds}, event, pid_facade_name) do
    reason = "Scheduled tear down of aggregate on #{inspect(event)}"
    Process.send_after(pid_facade_name, {:exit_process, pid, reason}, milliseconds)
  end
end
