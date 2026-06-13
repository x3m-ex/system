defmodule Banking.Api.MixProject do
  use Mix.Project

  def project do
    [
      app: :banking_api,
      version: "0.1.0",
      elixir: "~> 1.17",
      start_permanent: Mix.env() == :prod,
      deps: _deps(),
      elixirc_paths: ["lib"],
      dialyzer: [plt_add_deps: :apps_direct]
    ]
  end

  def cli do
    [preferred_envs: [bless: :test]]
  end

  def application do
    [
      extra_applications: [:logger],
      mod: {Banking.Api.Application, []}
    ]
  end

  defp _deps do
    [
      {:bandit, "~> 1.0"},
      {:plug, "~> 1.16"},
      {:jason, "~> 1.4"},
      {:x3m_system, path: "../../../.."},
      {:dialyxir, "~> 1.0", only: :dev, runtime: false},

      # local
      {:banking, path: "../banking"}
    ]
  end
end
