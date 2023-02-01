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

- `execute_on_new_aggregate returns `{:ok, -1}`if aggregate returns`:ok`response
with empty`events`

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
