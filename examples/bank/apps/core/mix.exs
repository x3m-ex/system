defmodule Banking.Core.MixProject do
  use Mix.Project

  def project do
    [
      app: :banking_core,
      version: "0.1.0",
      elixir: "~> 1.17",
      start_permanent: Mix.env() == :prod,
      deps: _deps(),
      elixirc_paths: _elixirc_paths(Mix.env()),
      dialyzer: [plt_add_deps: :apps_direct]
    ]
  end

  def cli do
    [preferred_envs: [bless: :test]]
  end

  def application do
    [
      extra_applications: [:logger],
      mod: {Banking.Core.Application, []}
    ]
  end

  defp _elixirc_paths(:test), do: ["lib", "test/support"]
  defp _elixirc_paths(_), do: ["lib"]

  defp _deps do
    [
      {:x3m_system, path: "../../../.."},
      {:ecto, "~> 3.12"},
      {:dialyxir, "~> 1.0", only: :dev, runtime: false},

      # local
      {:banking_event_store, path: "../event_store"},
      {:banking, path: "../banking"}
    ]
  end
end
