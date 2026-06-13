defmodule Banking.MixProject do
  use Mix.Project

  def project do
    [
      app: :banking,
      version: "0.1.0",
      elixir: "~> 1.17",
      start_permanent: false,
      deps: _deps(),
      elixirc_paths: ["lib"]
    ]
  end

  def application do
    [extra_applications: [:logger]]
  end

  defp _deps do
    [
      {:ecto, "~> 3.12"},
      {:ecto_sql, "~> 3.12"},
      {:telemetry, "~> 1.0"}
    ]
  end
end
