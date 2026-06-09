defmodule X3m.System.MixProject do
  use Mix.Project

  @version "0.9.1"
  @source_url "https://github.com/x3m-ex/system"

  def project do
    [
      app: :x3m_system,
      version: @version,
      elixir: "~> 1.17",
      source_url: @source_url,
      homepage_url: @source_url,
      description: """
      Building blocks for distributed and/or CQRS/ES systems
      """,
      package: _package(),
      start_permanent: true,
      test_coverage: [tool: ExCoveralls],
      name: "X3m System",
      docs: _docs(),
      aliases: _aliases(),
      deps: _deps(),
      dialyzer: [plt_add_apps: [:ex_unit, :local_cluster]],
      elixirc_paths: _elixirc_paths(Mix.env())
    ]
  end

  defp _docs do
    [
      main: "readme",
      source_ref: "v#{@version}",
      extras: [
        "README.md",
        "guides/getting-started.md",
        "guides/messaging.md",
        "guides/aggregates-and-event-sourcing.md",
        "guides/distribution.md",
        "guides/scheduling.md",
        "CHANGELOG.md"
      ],
      groups_for_extras: [
        Guides: ~r"guides/"
      ],
      groups_for_modules: [
        Messaging: [
          X3m.System.Message,
          X3m.System.Dispatcher,
          X3m.System.Router,
          X3m.System.Response
        ],
        "Aggregates & Event Sourcing": [
          X3m.System.MessageHandler,
          X3m.System.Aggregate,
          X3m.System.Aggregate.State,
          X3m.System.Aggregate.Repo
        ],
        Scheduling: [
          X3m.System.Scheduler
        ],
        Setup: [
          X3m.System.LocalAggregates,
          X3m.System.LocalAggregatesSupervision
        ]
      ]
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
        docs: :dev,
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
      files: [
        ".formatter.exs",
        "lib",
        "guides",
        "mix.exs",
        "README*",
        "CHANGELOG*",
        "LICENSE*"
      ],
      maintainers: ["Milan Burmaja"],
      licenses: ["MIT"],
      links: %{"GitHub" => @source_url}
    ]
  end
end
