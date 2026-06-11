# Start the current node in distributed mode once, so the whole suite runs under a
# named node (`:manager@127.0.0.1`). This keeps node-dependent assertions deterministic
# regardless of test ordering and lets the distributed tests spin up peer nodes.
:ok = LocalCluster.start()

ExUnit.start()

{:ok, _} = X3m.System.Test.Account.EventStore.start_link()
{:ok, _} = X3m.System.Test.Account.StateStore.start_link()

{:ok, _} =
  X3m.System.LocalAggregatesSupervision.start_link([
    X3m.System.Test.Account.LocalAggregates,
    X3m.System.Test
  ])

:ok = X3m.System.Test.Router.register_services()
