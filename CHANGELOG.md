# 0.9.2 (unreleased)

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
