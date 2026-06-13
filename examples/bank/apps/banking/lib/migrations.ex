defmodule Banking.Migrations do
  @moduledoc !"""
             Creates and migrates Ecto repos on application start.
             """
  require Logger

  @spec create(app :: atom()) :: :ok
  def create(app) do
    for repo <- _repos(app) do
      repo.__adapter__
      |> apply(:storage_up, [repo.config])
      |> case do
        :ok ->
          Logger.info(fn -> "The database for #{inspect(repo)} has been created" end)

        {:error, :already_up} ->
          Logger.debug(fn -> "The database for #{inspect(repo)} has already been created" end)

        {:error, term} when is_binary(term) ->
          Logger.warning(fn ->
            "The database for #{inspect(repo)} couldn't be created: #{term}"
          end)

        {:error, term} ->
          Logger.warning(fn ->
            "The database for #{inspect(repo)} couldn't be created: #{inspect(term)}"
          end)
      end
    end

    :ok
  end

  @spec up(app :: atom()) :: :ok
  def up(app) do
    for repo <- _repos(app) do
      {:ok, _, _} =
        Ecto.Migrator
        |> apply(:with_repo, [repo, &_run_migrator(&1, :up, all: true)])
    end

    :ok
  end

  defp _repos(app) do
    Application.load(app)
    Application.fetch_env!(app, :ecto_repos)
  end

  defp _run_migrator(repo, direction, opts),
    do: apply(Ecto.Migrator, :run, [repo, direction, opts])
end
