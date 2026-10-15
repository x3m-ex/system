# 0.10.1

- A rejected new-aggregate command (for example `{:validation_error, changeset}`) logs
  "New aggregate creation failed" at debug instead of warning
- `on_maybe_new_aggregate` creating a missing aggregate logs "No events found for aggregate" at
  debug instead of warning; `on_aggregate` still warns, now also when a
  `when_pid_is_not_registered/3` override returns `{:error, :not_found}`
- `on_maybe_new_aggregate` creates only when the aggregate is missing; a `{:error, :not_found}`
  from an existing aggregate command or from `save_events/1` is returned as is
- An aggregate repo that implements `stream_events/3` without default arguments no longer raises
  `UndefinedFunctionError` when an existing aggregate loads

# 0.10.0

- Generated ids (aggregate ids, transaction ids) are now UUIDv7, so they are time-ordered, and
  the `elixir_uuid` dependency is no longer needed: an app without it no longer crashes on an
  aggregate command
- `Message.prepare_aggregate_id/3` with `generate_if_missing: true` generates an id for a
  message created without a `raw_request` instead of raising `BadMapError`

## Upgrading from 0.9.6 or 0.9.7

Some of these changes already shipped in 0.9.7 without upgrade notes.

- **Generated ids are UUIDv7, not v4.** Ids from
  `Message.prepare_aggregate_id(..., generate_if_missing: true)` and transaction ids are
  time-ordered and carry their creation time in milliseconds, readable by anyone who sees the
  id. Action: drop checks for version 4 and don't expose generated ids where their creation
  time must stay private.
- **x3m_system no longer uses `elixir_uuid`.** Action: you may drop `{:elixir_uuid, ...}` from
  your deps unless your own code calls `UUID`.
- **`Scheduler.dispatch/3` can return `{:error, reason}`** (0.9.7) when `save_alarm/3` returns
  `{:error, reason}` or raises (`{:error, exception}`). Action: handle it instead of matching
  `:ok = MyScheduler.dispatch(...)`:
  ```elixir
  case MyScheduler.dispatch(msg, aggregate_id, in: 60_000) do
    :ok -> :ok
    {:error, reason} -> handle_not_scheduled(reason)
  end
  ```
  `save_alarm/3` may now return `{:error, reason}`, and a `load_alarms/3` error is retried on
  the next tick instead of crashing the scheduler; existing implementations need no change.
- **Scheduling a message id that is already scheduled is ignored** (0.9.7, as documented): the
  second `dispatch/3` returns `:ok` without calling `save_alarm/3`, and the message is delivered
  once. Action: give every alarm its own message, e.g. a fresh `Message.new/2` per alarm.
- **A raising `service_responded/2` no longer crashes the scheduler** (0.9.7): the failure is
  logged and the alarm is dropped from memory; it stays in your store and is only reloaded
  after a scheduler restart. Action: return `:ok` or `{:retry, in_ms, msg}` instead of raising.
- **`spawn_new_fun` in `when_pid_is_not_registered/3` can return `{:error, reason}`** (0.9.7),
  e.g. when the aggregate's `initial_state/0` raises. Action: in an override, pass the error
  through instead of matching `{:ok, pid} = spawn_new_fun.()`:
  ```elixir
  with {:ok, pid} <- spawn_new_fun.() do
    :ok = X3m.System.GenAggregate.set_state(pid, loaded_state, version)
    {:ok, pid}
  end
  ```
- **A crashed aggregate process is not restarted** (0.9.7); it used to come back as an
  unregistered, empty orphan. The next command for its id rehydrates it. Action: none, unless
  you monitor aggregate pids and expect a crashed one to come back.
- **The service registry keeps a node's services** (0.9.7): a router's services survive a
  stop/start of `:x3m_system`, a registry crash no longer withdraws them from peers, and
  stopping no longer pauses 10 seconds. Action: none, unless your tests restart `:x3m_system`
  expecting an empty registry or relied on the pause.
- **Scheduler log lines come from X3m.System.Scheduler.Server** (0.9.7), not from your
  scheduler module. Action: only if you filter logs by module.

# 0.9.7

- A crashed aggregate is no longer restarted as an unregistered, empty process; the next command
  for its id rehydrates it
- A duplicate create for a live aggregate no longer leaves an extra aggregate process behind, and
  an aggregate that fails to start returns an error to its caller and logs it
- Scheduler: a failing `load_alarms/3` logs a warning and retries the same window on the next
  tick instead of crashing; alarms loaded at or after the window end are armed instead of
  crashing it
- Scheduler: a message already scheduled in memory is ignored when scheduled or loaded again,
  as documented
- Scheduler: a raising `service_responded/2` or `save_alarm/3` is logged and no longer crashes
  the scheduler; `dispatch/3` returns `save_alarm/3`'s `{:error, reason}`, or
  `{:error, exception}` when it raises
- Scheduler: alarms are loaded `2 * in_memory_interval/0` ahead of now on every tick, instead of
  a window that grew with each tick
- `X3m.System.Response` documents the `{:error, :wrong_expected_version, version}` and
  `{:error, :key_already_registered, pid}` responses aggregate-backed commands can return
- A crashed service registry restarts with the node's own services instead of taking the
  `:x3m_system` application down, and stopping it no longer waits 10 seconds
- A node whose `:x3m_system` application starts after it joined the cluster sees its peers'
  services at once, instead of after the next 20-second exchange
- Compiling `x3m_system` without the optional `elixir_uuid` no longer warns that
  `UUID.uuid4/0` is undefined

# 0.9.6

- `X3m.System.Aggregate.initial_state/1` results pass dialyzer when given to a generated
  command function; build a `State` with it rather than a literal `%State{}`

# 0.9.5

- Fix repeated dry runs on new aggregates, failed event saves or commit timeouts crashing the
  aggregate supervisor and taking every live aggregate down; they also no longer leave orphaned
  processes. A commit timeout logs an explicit warning instead of a GenServer crash report
- A dry run on a new aggregate, valid or rejected, no longer logs warnings; the aggregate
  registry logs intentional aggregate shutdowns (`:normal`, `:shutdown`, `{:shutdown, _}`) at
  debug instead of warning
- When a dry run on a new aggregate or a failed event save returns, its aggregate is already
  gone, so an immediate real command on the same id gets a fresh aggregate
- In a message handler, `exit_process/2` (and the `unload_aggregate_on` `:unload` rule) returns
  once the aggregate is gone
- A command whose aggregate dies before committing (e.g. on a commit timeout) fails at once
  instead of after a further second

# 0.9.4

- Service discovery no longer serializes through the registry process; with the registry
  not running, dispatch and `authorized?` report the service unavailable instead of
  exiting the caller
- A router's `register_services/0` returns once its services are discoverable on
  its own node
- Peers learn the public services of every router registered on a node, not only the
  last one

# 0.9.3

- Fix `Dispatcher.dispatch/2` waiting for the timeout (forever with `:infinity`) when a
  remote service returns other than `:ok`; any non-`:ok` service return, local or remote,
  is now `{:error, {:badrpc, {:bad_return, value}}}`
- A dispatch whose relay crashes returns `{:error, {:badrpc, {:EXIT, reason}}}` at once
  instead of waiting for the timeout

# 0.9.2

- Fix `Dispatcher.dispatch/2` `:timeout` not firing while a remote handler blocks
- Fix a reply arriving after a dispatch timeout leaking into the caller's mailbox
- Return `{:error, {:badrpc, reason}}` instead of crashing when a remote call fails
  (node down, handler raised, exited or threw)
- A local handler that raises, exits or throws returns `{:error, {:badrpc, reason}}` at
  once, as a remote one does, instead of `service_timeout` after the full timeout
- A timed-out dispatch does not cancel its handler, so hung remote handlers now
  accumulate per dispatch rather than per caller; providers should bound their own work
- Invoke remote services over `:erpc`
- Add a `:timeout` option to `Dispatcher.authorized?/2` (default 5s) for a remote check
- `Dispatcher.authorized?` asks the next provider when a remote one fails, and returns
  `{:error, {:badrpc, reason}}` instead of a raw `{:badrpc, reason}` when all fail
- Fix the `Dispatcher.authorized?` spec: `:service_unavailable` is returned as a bare atom
- Add a Telemetry guide documenting every event, its measurements and units
- Fix hexdocs "view source" links to point at the version tag

# 0.9.1

- Add set_state optional callback to Aggregate
- Add documentation.

# 0.9.0

- Breaking change in telemetry events from dispatcher and router

# 0.8.6

- Fix dialyzer error for `:ensure_local_logging?`
- Change local logging to be turned on by default

# 0.8.5

- Fix typo in raised ArgumentError if passed `:ensure_local_logging?` value is
  not `boolean()`
- Refactor internal function to eliminate dialyzer error from client apps

# 0.8.4

- Bump elixir to 1.11
- Fix return types in spec for `Router.authorize/1`
- Update deps
- Clean unused deps
- Add optional `:ensure_local_logging?` config option when defining a Router to
  limit each node log output to its own STDOUT
  - If passed as `true` ensures log messages of called node are not shown in
    caller node STDOUT
  - If not passed defaults to `false`

# 0.8.3

- Logger.warn -> Logger.warning

# 0.8.2

- Add `Dispatcher.validate/1` function that will set `Message.dry_run` to `true` if it was `false`.
- Add optional `Aggregate.rollback/2` callback that is invoked if message was dry run.
- Add optional `Aggregate.commit/2` callback that is invoked if message wasn't dry run.

# 0.8.1

- Router calls `authorize/1` callback before it proceeds with service call.
  BREAKING CHANGE: by default `authorize/1` returns `:forbidden`.
- Add `Dispatcher.authorized?/1`

# 0.7.20

- Dispatcher creates temp proc when invoking local service (to avoid refc binary leaks)

# 0.7.19

- No need for catch-all function when unloading aggregate on state

# 0.7.18

- Add unload aggregate on it's state (after applying events) using MessageHandler macro option:

```
use X3m.System.MessageHandler,
  unload_aggregate_on: %{
    state: &__MODULE__.unload_on_state/1
  }

def unload_on_state(%ClientState{status: :completed}), do: :unload
def unload_on_state(%ClientState{status: :almost_completed}), do: {:in, :timer.hours(1)}
def unload_on_state(%ClientState{}), do: :skip
```

# 0.7.17

- Add unload aggregate on event using MessageHandler macro option:

```
use X3m.System.MessageHandler,
  unload_aggregate_on: %{
    events: %{
      Event.Example => {:in, :timer.hours(1)}
    }
  }
```

# 0.7.16

- `execute_on_new_aggregate` returns `{:ok, -1}` if aggregate returns `:ok` response
  with empty `events`

# 0.7.15

- Add `on_maybe_new_aggregate/2` in .formatter

# 0.7.14

- Add `on_maybe_new_aggregate/2` macro for MessageHandler.

# 0.7.13

- Service router doesn't remove `events` from `Message` if `dry_run` was set to `:verbose`

# 0.7.9

- Add and maintain `dispatch_attempts` in SysMsg for scheduler

# 0.7.5

- Introduce servicep/2 macro for router.

# 0.7.2

- Fix warnings in elixir 1.11

# 0.7.1

- Service router removes `request` and `events` from `Message` when sending response back to invoker.
