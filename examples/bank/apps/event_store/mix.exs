defmodule Banking.EventStore.MixProject do
  use Mix.Project

  def project do
    [
      app: :banking_event_store,
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
      {:jason, "~> 1.4"},
      {:extreme, "~> 1.0"},
      {:x3m_system, path: "../../../.."},
      {:postgrex, "~> 0.19", optional: true},
      {:ecto, "~> 3.12", optional: true},
      {:ecto_sql, "~> 3.12", optional: true},

      # local
      {:banking, path: "../banking"}
    ]
  end
end
