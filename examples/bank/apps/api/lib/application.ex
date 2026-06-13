defmodule Banking.Api.Application do
  @moduledoc false
  use Application

  def start(_type, _args) do
    Banking.TelemetryLogger.setup()

    port =
      System.get_env("BANKING_API_PORT", "4001")
      |> String.to_integer()

    children = [
      {Bandit, plug: Banking.Api.Router, port: port}
    ]

    opts = [strategy: :one_for_one, name: Banking.Api.MainSupervisor]
    Supervisor.start_link(children, opts)
  end
end
