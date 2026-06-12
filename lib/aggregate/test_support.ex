defmodule X3m.System.Aggregate.TestSupport do
  @moduledoc """
  Helpers for testing aggregates as pure functions, in a given/when/then style.

  An aggregate command is a plain function
  `cmd(X3m.System.Message.t(), X3m.System.Aggregate.State.t())` returning
  `{:block | :noblock, message, state}`. To test one:

    * **given** - `state_from_events/3` rebuilds the state from prior events;
    * **when** - `command_message/3` builds the message; you call the command;
    * **then** - `apply_events/4` folds the events the command emitted onto the given
      state so you can assert the resulting `client_state`.

  No aggregate process or event store is involved.
  """
  alias X3m.System.{Aggregate, Message}

  @doc """
  Builds a `X3m.System.Message` for `service_name`, with `raw_request` and each entry of
  `assigns` applied via `X3m.System.Message.assign/3`.

  ## Examples

      iex> msg = X3m.System.Aggregate.TestSupport.command_message(:open_account, %{"id" => "a1"}, %{invoked_by: %{admin?: true}})
      iex> {msg.service_name, msg.raw_request, msg.assigns}
      {:open_account, %{"id" => "a1"}, %{invoked_by: %{admin?: true}}}
  """
  @spec command_message(service_name :: atom, raw_request :: map, assigns :: map) :: Message.t()
  def command_message(service_name, raw_request \\ %{}, assigns \\ %{}) do
    service_name
    |> Message.new(raw_request: raw_request)
    |> _apply_assigns(assigns)
  end

  @doc """
  Folds `events` onto an existing `state` via `aggregate_mod`'s generated `apply_events/3`.

  Options:

    * `:version` - version to stamp on the result. Defaults to
      `state.version + length(events)`.
  """
  @spec apply_events(
          aggregate_mod :: module,
          state :: Aggregate.State.t(),
          events :: [any],
          opts :: Keyword.t()
        ) :: Aggregate.State.t()
  def apply_events(aggregate_mod, %Aggregate.State{} = state, events, opts \\ []) do
    version = Keyword.get(opts, :version, state.version + length(events))
    aggregate_mod.apply_events(events, version, state)
  end

  @doc """
  Builds the state you'd have after `events` were applied to `aggregate_mod`'s initial
  state - `apply_events/4` starting from `X3m.System.Aggregate.initial_state/1`.

  Options:

    * `:version` - version to stamp on the result. Defaults to `length(events) - 1`
      (initial version `-1` plus one per event), matching a fresh stream.
  """
  @spec state_from_events(aggregate_mod :: module, events :: [any], opts :: Keyword.t()) ::
          Aggregate.State.t()
  def state_from_events(aggregate_mod, events, opts \\ []),
    do: apply_events(aggregate_mod, Aggregate.initial_state(aggregate_mod), events, opts)

  @spec _apply_assigns(Message.t(), map) :: Message.t()
  defp _apply_assigns(message, assigns),
    do: Enum.reduce(assigns, message, fn {key, val}, msg -> Message.assign(msg, key, val) end)
end
