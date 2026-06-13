defmodule Banking.Core.Aggregates.Account.Aggregate do
  @moduledoc """
  Account aggregate — handles commands and applies events.

  All commands require the caller to be either the account owner or an admin
  (instance authorization via `admin_or_owner?/2` guard).
  """
  use X3m.System.Aggregate
  alias X3m.System.Message, as: SysMsg
  alias Banking.Core.Aggregates.Account.{State, Commands, Events}

  defguardp admin_or_owner?(assigns, owner_id)
            when assigns.invoked_by.admin? == true or
                   assigns.invoked_by.user_id == owner_id

  @impl X3m.System.Aggregate
  def initial_state, do: %State{}

  handle_msg :open_account, &Commands.Open.new/2, fn
    %SysMsg{request: cmd} = msg, %State{} = state ->
      event = %Events.Opened{id: cmd.id, owner_id: cmd.owner_id}

      msg =
        msg
        |> SysMsg.add_event(event)
        |> SysMsg.created(cmd.id)

      {:block, msg, state}
  end

  handle_msg :deposit, &Commands.Deposit.new/2, fn
    %SysMsg{assigns: assigns, request: cmd} = msg, %State{owner_id: owner_id} = state
    when admin_or_owner?(assigns, owner_id) ->
      event = %Events.Deposited{id: cmd.id, amount: cmd.amount}

      msg =
        msg
        |> SysMsg.add_event(event)
        |> SysMsg.ok()

      {:block, msg, state}

    %SysMsg{} = msg, %State{} = state ->
      {:noblock, SysMsg.error(msg, :forbidden), state}
  end

  handle_msg :withdraw, &Commands.Withdraw.new/2, fn
    %SysMsg{assigns: assigns, request: cmd} = msg,
    %State{owner_id: owner_id} = state
    when admin_or_owner?(assigns, owner_id) ->
      event = %Events.Withdrawn{id: cmd.id, amount: cmd.amount}

      msg =
        msg
        |> SysMsg.add_event(event)
        |> SysMsg.ok()

      {:block, msg, state}

    %SysMsg{} = msg, %State{} = state ->
      {:noblock, SysMsg.error(msg, :forbidden), state}
  end

  handle_msg :close_account, fn
    %SysMsg{} = msg, %State{closed?: true} = state ->
      {:noblock, SysMsg.error(msg, {:conflict, "account is closed"}), state}

    %SysMsg{assigns: assigns} = msg, %State{owner_id: owner_id} = state
    when admin_or_owner?(assigns, owner_id) ->
      _close(msg, state)

    %SysMsg{} = msg, %State{} = state ->
      {:noblock, SysMsg.error(msg, :forbidden), state}
  end

  def processed_message_id(%{message_id: id}), do: id

  def apply_event(%Events.Opened{} = e, %State{} = state),
    do: %State{state | id: e.id, owner_id: e.owner_id}

  def apply_event(%Events.Deposited{} = e, %State{} = state),
    do: %State{state | balance: state.balance + e.amount}

  def apply_event(%Events.Withdrawn{} = e, %State{} = state),
    do: %State{state | balance: state.balance - e.amount}

  def apply_event(%Events.Closed{}, %State{} = state),
    do: %State{state | closed?: true}

  defp _close(%SysMsg{} = msg, %State{id: id, balance: balance} = state) do
    events =
      if balance > 0,
        do: [%Events.Withdrawn{id: id, amount: balance}, %Events.Closed{id: id}],
        else: [%Events.Closed{id: id}]

    msg =
      events
      |> Enum.reduce(msg, fn event, acc -> SysMsg.add_event(acc, event) end)
      |> SysMsg.ok()

    {:block, msg, state}
  end
end
