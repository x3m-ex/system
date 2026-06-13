defmodule Mix.Tasks.Bless do
  @moduledoc !"""
             Runs all checks required to push project to repo.
             """
  use Mix.Task

  @shortdoc "Runs all checks (compile, format, test, dialyzer)"
  def run(_) do
    [
      {"compile", ["--force"]},
      {"format", ["--check-formatted"]},
      {"test", []},
      {"dialyzer", []}
    ]
    |> Enum.each(fn {task, args} ->
      IO.ANSI.format([:cyan, "Running #{task} with args #{inspect(args)}"])
      |> IO.puts()

      Mix.Task.run(task, args)
    end)
  end
end
