defmodule Mix.Tasks.Bless do
  @moduledoc !"""
             Runs all checks required to push project to repo.
             """
  use Mix.Task

  @shortdoc "Runs all checks (compile, format, test, dialyzer)"
  def run(_args) do
    [
      {"compile", ["--force"]},
      {"format", ["--check-formatted"]},
      {"test", []}
    ]
    |> Enum.each(fn {task, args} ->
      _announce(task, args)
      Mix.Task.run(task, args)
    end)

    _announce("dialyzer", [])
    _dialyzer()
  end

  defp _announce(task, args) do
    [:cyan, "Running #{task} with args #{inspect(args)}"]
    |> IO.ANSI.format()
    |> IO.puts()
  end

  # own OS process: in-VM, a recompiled path dep prunes :dialyzer off the code path
  defp _dialyzer do
    "mix"
    |> System.cmd(["dialyzer"], env: [{"MIX_ENV", to_string(Mix.env())}], into: IO.stream())
    |> case do
      {_output, 0} -> :ok
      {_output, status} -> Mix.raise("dialyzer failed with exit status #{status}")
    end
  end
end
