# Scheduling

`X3m.System.Scheduler` delivers a `X3m.System.Message` at some point in the future. Think
of it as a **persistable `Process.send_after/3`**: scheduled messages survive a restart
because you persist them, and they are dispatched through the normal
`X3m.System.Dispatcher` when their time comes.

The scheduler is backend-agnostic and standalone — it doesn't require aggregates or any
particular store. It needs the optional `:tzdata` dependency.

## Defining a scheduler

`use X3m.System.Scheduler` and implement the callbacks that persist and load alarms:

```elixir
defmodule MyApp.Scheduler do
  use X3m.System.Scheduler
  alias X3m.System.Message, as: SysMsg

  @impl X3m.System.Scheduler
  def save_alarm(%SysMsg{} = msg, aggregate_id, repo) do
    repo.insert_alarm(msg, aggregate_id, msg.assigns.dispatch_at)
    :ok
  end

  @impl X3m.System.Scheduler
  def load_alarms(from, until, repo) do
    {:ok, repo.alarms_between(from, until)}
  end

  @impl X3m.System.Scheduler
  def service_responded(%SysMsg{} = msg, repo) do
    repo.delete_alarm(msg.id)
    :ok
  end
end
```

Start it with the state that every callback receives as its last argument — typically
your repo or any context the callbacks need:

```elixir
{:ok, _pid} = MyApp.Scheduler.start_link(MyApp.AlarmsRepo)
```

(Add it to your supervision tree the same way.)

## Scheduling a message

Use `dispatch/3` with either a delay `in:` milliseconds or an absolute `at:`
`DateTime`:

```elixir
msg = X3m.System.Message.new(:send_reminder, raw_request: %{"id" => "acc-1"})

# in one hour
MyApp.Scheduler.dispatch(msg, "acc-1", in: 60 * 60 * 1_000)

# at a specific time
MyApp.Scheduler.dispatch(msg, "acc-1", at: ~U[2026-01-01 09:00:00Z])
```

The scheduler assigns the resolved `:dispatch_at` onto the message, calls your
`save_alarm/3` so it is persisted, and arms delivery. When the time arrives the message
is sent through `X3m.System.Dispatcher.dispatch/2` to its `service_name`.

## Persistence and the in-memory window

Not every future alarm is kept in memory. The scheduler loads alarms in bulk every
`in_memory_interval/0` milliseconds, covering the next `2 * in_memory_interval/0`
window. On startup it calls `load_alarms/3` with `from: nil`; after that, `from` is the
previous `until`. This is why you persist alarms in `save_alarm/3` and reload them in
`load_alarms/3` — a far-future alarm may be persisted now and only loaded into memory
shortly before it is due, and it is reloaded after a restart.

If a message with the same `X3m.System.Message.id` is already scheduled in memory, it is
ignored (so duplicate scheduling is safe within a window).

## Retries

After a scheduled message is dispatched, `service_responded/2` is called with the
resolved message. Return:

- `:ok` — delivery succeeded; drop the alarm (delete it from your store).
- `{:retry, in_ms, message}` — redeliver `message` in `in_ms` milliseconds.

You can track attempts via the message's `assigns`:

```elixir
@impl X3m.System.Scheduler
def service_responded(%SysMsg{response: {:ok, _}} = msg, repo) do
  repo.delete_alarm(msg.id)
  :ok
end

def service_responded(%SysMsg{assigns: %{dispatch_attempts: n}} = msg, _repo) when n < 5 do
  {:retry, 30_000, msg}
end

def service_responded(%SysMsg{} = msg, repo) do
  repo.mark_failed(msg.id)
  :ok
end
```

`dispatch_attempts` is incremented for you on each delivery.

## Optional callbacks

Two callbacks have defaults you can override:

- `in_memory_interval/0` — how often (ms) alarms are loaded into memory. Default is 6
  hours.
- `dispatch_timeout/1` — how long (ms) to wait for the dispatched service to respond.
  Default is 5000.
