defmodule Banking.Listeners.MixProject do
  use Mix.Project

  def project do
    [
      app: :banking_listeners,
      version: "0.1.0",
      elixir: "~> 1.17",
      start_permanent: Mix.env() == :prod,
      deps: _deps(),
      elixirc_paths: _elixirc_paths(Mix.env()),
      dialyzer: [
        plt_add_deps: :apps_direct,
        plt_add_apps: [:ecto, :extreme, :jason, :x3m_system]
      ]
    ]
  end

  def cli do
    [preferred_envs: [bless: :test]]
  end

  def application do
    [
      extra_applications: [:logger],
      mod: {Banking.Listeners.Application, []}
    ]
  end

  defp _elixirc_paths(:test), do: ["lib", "test/support"]
  defp _elixirc_paths(_), do: ["lib"]

  defp _deps do
    [
      {:postgrex, "~> 0.19"},
      {:ecto_sql, "~> 3.12"},
      {:x3m_system, path: "../../../.."},
      {:dialyxir, "~> 1.0", only: :dev, runtime: false},

      # local
      {:banking_event_store, path: "../event_store"},
      {:banking, path: "../banking"}
    ]
  end
end
