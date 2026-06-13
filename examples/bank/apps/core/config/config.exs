import Config

import_config "../../banking/config/config.exs"

config :banking_core, Banking.Core.EventStore,
  db_type: "node",
  host: "localhost",
  port: "1113",
  username: "admin",
  password: "changeit",
  connection_name: "banking_core"

import_config "#{Mix.env()}.exs"
