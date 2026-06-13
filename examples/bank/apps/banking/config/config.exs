import Config

config :logger, :console,
  format: "$date $time $metadata[$level] $message\n",
  level: :debug,
  metadata: [:request_id, :corr_id, :pid]

import_config "#{Mix.env()}.exs"
