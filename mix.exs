defmodule X3m.System.MixProject do
  use Mix.Project

  def project do
    [
      app: :x3m_system,
      version: "0.9.1",
      elixir: "~> 1.17",
      source_url: "https://github.com/x3m-ex/system",
      description: """
      Building blocks for distributed and/or CQRS/ES systems
      """,
      package: _package(),
      start_permanent: true,
      test_coverage: [tool: ExCoveralls],
      name: "X3m System",
      aliases: _aliases(),
      deps: _deps(),
      dialyzer: [plt_add_apps: [:ex_unit, :local_cluster]],
      elixirc_paths: _elixirc_paths(Mix.env())
    ]
  end

  def application do
    [
      mod: {X3m.System.Application, []},
      extra_applications: [:logger]
    ]
  end

  def cli do
    [
      preferred_envs: [
        coveralls: :test,
        "coveralls.detail": :test,
        "coveralls.post": :test,
        "coveralls.html": :test,
        dialyzer: :test,
        bless: :test
      ]
    ]
  end

  defp _elixirc_paths(:test), do: ["lib", "test/support"]
  defp _elixirc_paths(_), do: ["lib"]

  defp _deps do
    [
      {:telemetry, "~> 0.4 or ~> 1.0"},
      # needed when working with aggregates
      {:elixir_uuid, "~> 1.2", optional: true},
      # needed for use of X3m.System.Scheduller
      {:tzdata, "~> 1.0", optional: true},

      # test dependencies
      {:local_cluster, "~> 2.0", only: [:test], runtime: false},
      {:dialyxir, "~> 1.1", only: [:test, :dev], runtime: false},
      {:ex_doc, "~> 0.21", only: [:dev, :test], runtime: false},
      {:excoveralls, "~> 0.13", only: :test}
    ]
  end

  defp _aliases do
    [
      bless: [&_bless/1]
    ]
  end

  defp _bless(_) do
    [
      {"format", ["--check-formatted"]},
      {"compile", ["--warnings-as-errors", "--force"]},
      {"coveralls.html", []},
      {"dialyzer", []},
      {"docs", []}
    ]
    |> Enum.each(fn {task, args} ->
      IO.ANSI.format([:cyan, "Running #{task} with args #{inspect(args)}"])
      |> IO.puts()

      Mix.Task.run(task, args)
    end)
  end

  defp _package do
    [
      files: [".formatter.exs", "lib", "mix.exs", "README*", "LICENSE*"],
      maintainers: ["Milan Burmaja"],
      licenses: ["MIT"],
      links: %{"GitHub" => "https://github.com/x3m-ex/system"}
    ]
  end
end
