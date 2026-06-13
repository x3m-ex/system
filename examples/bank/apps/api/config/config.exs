import Config

import_config "../../banking/config/config.exs"

config :banking_api, port: 4001

import_config "#{Mix.env()}.exs"
