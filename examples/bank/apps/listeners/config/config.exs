import Config

import_config "../../banking/config/config.exs"

config :banking_listeners, ecto_repos: [Banking.Listeners.Repo]

config :banking_listeners, Banking.Listeners.EventStore,
  db_type: "node",
  host: "localhost",
  port: "1113",
  username: "admin",
  password: "changeit",
  connection_name: "banking_listeners"

config :banking_listeners, Banking.Listeners.Repo,
  adapter: Ecto.Adapters.Postgres,
  username: "postgres",
  password: "postgres",
  database: "banking",
  hostname: "localhost",
  pool_size: 5

import_config "#{Mix.env()}.exs"
