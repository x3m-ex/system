defmodule X3m.System.Test.Account.Aggregate do
  @moduledoc false
  use X3m.System.Aggregate
  alias X3m.System.Message, as: SysMsg
  alias X3m.System.Test.Account.{State, Commands, Events}

  @impl X3m.System.Aggregate
  def initial_state, do: %State{}

  handle_msg :open_account, &Commands.Open.new/2, fn %SysMsg{request: cmd} = msg,
                                                     %State{} = state ->
    event = %Events.Opened{id: cmd.id, owner_id: cmd.owner_id}
    {:block, msg |> SysMsg.add_event(event) |> SysMsg.created(cmd.id), state}
  end

  handle_msg :deposit, &Commands.Deposit.new/2, fn %SysMsg{request: cmd} = msg,
                                                   %State{} = state ->
    event = %Events.Deposited{id: cmd.id, amount: cmd.amount}
    {:block, msg |> SysMsg.add_event(event) |> SysMsg.ok(), state}
  end

  handle_msg :withdraw, &Commands.Withdraw.new/2, fn %SysMsg{request: cmd} = msg,
                                                     %State{balance: balance} = state ->
    if cmd.amount <= balance do
      event = %Events.Withdrawn{id: cmd.id, amount: cmd.amount}
      {:block, msg |> SysMsg.add_event(event) |> SysMsg.ok(), state}
    else
      event = %Events.WithdrawalRejected{id: cmd.id, amount: cmd.amount, balance: balance}
      {:block, msg |> SysMsg.add_event(event) |> SysMsg.error(:insufficient_funds), state}
    end
  end

  handle_msg :ensure_account, &Commands.Open.new/2, fn
    %SysMsg{request: cmd} = msg, %State{id: nil} = state ->
      event = %Events.Opened{id: cmd.id, owner_id: cmd.owner_id}

      msg =
        msg
        |> SysMsg.add_event(event)
        |> SysMsg.created(cmd.id)

      {:block, msg, state}

    %SysMsg{request: %Commands.Open{owner_id: owner_id}} = msg,
    %State{owner_id: owner_id} = state ->
      # owner unchanged -> no-op (no event)
      {:noblock, SysMsg.ok(msg), state}

    %SysMsg{request: cmd} = msg, %State{} = state ->
      event = %Events.OwnerChanged{id: cmd.id, owner_id: cmd.owner_id}
      {:block, msg |> SysMsg.add_event(event) |> SysMsg.ok(), state}
  end

  handle_msg :close_account, fn
    %SysMsg{assigns: %{invoked_by: %{admin?: true}}} = msg, %State{} = state ->
      _close(msg, state)

    %SysMsg{assigns: %{invoked_by: %{user_id: uid}}} = msg, %State{owner_id: uid} = state ->
      _close(msg, state)

    %SysMsg{} = msg, %State{} = state ->
      {:noblock, SysMsg.error(msg, :forbidden), state}
  end

  def processed_message_id(%{message_id: id}), do: id

  def apply_event(%Events.Opened{} = e, %State{} = state),
    do: %State{state | id: e.id, owner_id: e.owner_id}

  def apply_event(%Events.OwnerChanged{} = e, %State{} = state),
    do: %State{state | owner_id: e.owner_id}

  def apply_event(%Events.Deposited{} = e, %State{} = state),
    do: %State{state | balance: state.balance + e.amount}

  def apply_event(%Events.Withdrawn{} = e, %State{} = state),
    do: %State{state | balance: state.balance - e.amount}

  def apply_event(%Events.WithdrawalRejected{} = e, %State{} = state),
    do: %State{
      state
      | highest_rejected_withdrawal: max(state.highest_rejected_withdrawal, e.amount)
    }

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
