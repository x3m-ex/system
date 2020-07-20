defmodule X3m.System.MixProject do
  use Mix.Project

  def project do
    [
      app: :x3m_system,
      version: "0.6.3",
      elixir: "~> 1.7",
      source_url: "https://github.com/x3m-ex/system",
      description: """
      Building blocks for distributed systems
      """,
      package: _package(),
      start_permanent: true,
      test_coverage: [tool: ExCoveralls],
      preferred_cli_env: [
        coveralls: :test,
        "coveralls.detail": :test,
        "coveralls.post": :test,
        "coveralls.html": :test,
        dialyzer: :dev,
        bless: :test
      ],
      name: "X3m System",
      aliases: _aliases(),
      deps: _deps(),
      elixirc_paths: _elixirc_paths(Mix.env())
    ]
  end

  def application do
    [
      mod: {X3m.System.Application, []},
      extra_applications: [:logger]
    ]
  end

  defp _elixirc_paths(:test), do: ["lib", "test/support"]
  defp _elixirc_paths(_), do: ["lib"]

  defp _deps do
    [
      {:elixir_uuid, "~> 1.2"},
      {:telemetry, "~> 0.4"},
      # needed for use of X3m.System.Scheduller
      {:tzdata, "~> 1.0", optional: true},

      # test dependencies
      {:dialyxir, "~> 1.0.0-rc.6", only: [:test, :dev], runtime: false},
      {:ex_doc, "~> 0.21", only: [:dev, :test], runtime: false},
      {:excoveralls, "~> 0.12", only: :test}
    ]
  end

  defp _aliases do
    [
      bless: [&_bless/1]
    ]
  end

  defp _bless(_) do
    [
      {"compile", ["--warnings-as-errors", "--force"]},
      {"format", ["--check-formatted"]},
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
