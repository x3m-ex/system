defmodule Banking.Listeners.Accounts.Denormalizer do
  @moduledoc !"""
             Upserts account events into the read model.
             """
  import Ecto.Query
  alias Banking.Listeners.Repo
  alias Banking.Listeners.Accounts.Model
  alias X3m.System.Message, as: SysMsg
  alias Banking.Core.Aggregates.Account.Events

  @spec denormalize(msg :: SysMsg.t()) :: {:reply, SysMsg.t()}
  def denormalize(
        %SysMsg{
          assigns: %{on_event: Events.Opened},
          raw_request: %{id: id, owner_id: owner_id}
        } = msg
      ) do
    %Model{id: id, owner_id: owner_id, balance: 0, status: "open"}
    |> Repo.insert!(on_conflict: :nothing)

    {:reply, SysMsg.ok(msg)}
  end

  def denormalize(
        %SysMsg{
          assigns: %{on_event: Events.Deposited},
          raw_request: %{id: id, amount: amount}
        } = msg
      ) do
    from(a in Model, where: a.id == ^id)
    |> Repo.update_all(inc: [balance: amount])

    {:reply, SysMsg.ok(msg)}
  end

  def denormalize(
        %SysMsg{
          assigns: %{on_event: Events.Withdrawn},
          raw_request: %{id: id, amount: amount}
        } = msg
      ) do
    from(a in Model, where: a.id == ^id)
    |> Repo.update_all(inc: [balance: -amount])

    {:reply, SysMsg.ok(msg)}
  end

  def denormalize(
        %SysMsg{
          assigns: %{on_event: Events.Closed},
          raw_request: %{id: id}
        } = msg
      ) do
    from(a in Model, where: a.id == ^id)
    |> Repo.update_all(set: [status: "closed"])

    {:reply, SysMsg.ok(msg)}
  end
end
