# Start the current node in distributed mode once, so the whole suite runs under a
# named node (`:manager@127.0.0.1`). This keeps node-dependent assertions deterministic
# regardless of test ordering and lets the distributed tests spin up peer nodes.
:ok = LocalCluster.start()

ExUnit.start()

:ok = X3m.System.Test.Router.register_services()
