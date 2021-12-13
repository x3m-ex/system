# 0.7.16
  * `execute_on_new_aggregate returns `{:ok, -1}` if aggregate returns `:ok` response
    with empty `events`

# 0.7.15
  * Add `on_maybe_new_aggregate/2` in .formatter

# 0.7.14
  * Add `on_maybe_new_aggregate/2` macro for MessageHandler.

# 0.7.13
  * Service router doesn't remove `events` from `Message` if `dry_run` was set to `:verbose`

# 0.7.9
  * Add and maintain `dispatch_attempts` in SysMsg for scheduler

# 0.7.5
  * Introduce servicep/2 macro for router.

# 0.7.2
  * Fix warnings in elixir 1.11

# 0.7.1
  * Service router removes `request` and `events` from `Message` when sending response back to invoker.
