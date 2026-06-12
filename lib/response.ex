defmodule X3m.System.Response do
  @moduledoc """
  The set of responses a service call can return.

  Every `X3m.System.Message` carries a `response` field. By the time a dispatched
  message comes back to the caller, that field holds one of the values described by
  `t:t/0`. Callers (controllers, other services, tests) typically `case`/pattern-match
  on it:

      case Dispatcher.dispatch(message) do
        %X3m.System.Message{response: {:created, id, _version}} -> ...
        %X3m.System.Message{response: {:validation_error, changeset}} -> ...
        %X3m.System.Message{response: {:error, reason}} -> ...
      end

  The functions in this module are thin constructors for those shapes. You rarely call
  them directly — `X3m.System.Message.ok/1`, `created/2`, `error/2` and friends build
  them for you — but they document the full vocabulary of responses the system speaks.

  ## Response shapes

    * `:ok` / `{:ok, payload}` / `{:ok, payload, version}` — success. The 3-tuple is
      returned by aggregate-backed services and carries the aggregate's new version.
    * `{:created, id}` / `{:created, id, version}` — a new aggregate was created.
    * `{:validation_error, request}` — the request failed validation (e.g. an invalid
      `Ecto.Changeset`).
    * `{:missing_id, id_field}` — the request did not contain the expected aggregate id.
    * `{:service_unavailable, service_name}` — no node in the cluster offers the service.
    * `{:service_timeout, service_name, message_id, timeout}` — the service did not reply
      within the dispatch timeout.
    * `{:error, reason}` — any other domain or infrastructure error.
  """

  @type t ::
          :ok
          | {:ok, payload :: any}
          | {:ok, payload :: any, version :: integer}
          | {:created, id :: any}
          | {:created, id :: any, version :: integer}
          | {:service_unavailable, service_name :: atom}
          | {:service_timeout, service_name :: atom, message_id :: String.t(),
             timeout :: non_neg_integer}
          | {:validation_error, request :: map}
          | {:missing_id, id_field :: atom | String.t()}
          | {:error, reason :: any}

  @doc """
  Builds the bare success response.

  ## Examples

      iex> X3m.System.Response.ok()
      :ok
  """
  @spec ok() :: :ok
  def ok, do: :ok

  @doc """
  Builds a success response carrying a `payload`.

  ## Examples

      iex> X3m.System.Response.ok(%{balance: 10})
      {:ok, %{balance: 10}}
  """
  @spec ok(payload :: any) :: {:ok, payload :: any}
  def ok(payload), do: {:ok, payload}

  @doc """
  Builds a response signalling that a new aggregate with `id` was created.

  ## Examples

      iex> X3m.System.Response.created("acc-1")
      {:created, "acc-1"}
  """
  @spec created(id :: any) :: {:created, id :: any}
  def created(id), do: {:created, id}

  @doc """
  Builds a response signalling that no node offers `msg_name`.

  ## Examples

      iex> X3m.System.Response.service_unavailable(:open_account)
      {:service_unavailable, :open_account}
  """
  @spec service_unavailable(service_name :: atom) :: {:service_unavailable, service_name :: atom}
  def service_unavailable(msg_name), do: {:service_unavailable, msg_name}

  @doc """
  Builds a response signalling that `msg_name` (with message id `req_id`) did not
  reply within `timeout` milliseconds.

  ## Examples

      iex> X3m.System.Response.service_timeout(:open_account, "req-1", 5_000)
      {:service_timeout, :open_account, "req-1", 5_000}
  """
  @spec service_timeout(
          service_name :: atom,
          message_id :: String.t(),
          timeout :: non_neg_integer
        ) ::
          {:service_timeout, service_name :: atom, message_id :: String.t(),
           timeout :: non_neg_integer}
  def service_timeout(msg_name, req_id, timeout),
    do: {:service_timeout, msg_name, req_id, timeout}

  @doc """
  Builds an unauthorized response with an explanatory `msg`.

  ## Examples

      iex> X3m.System.Response.unauthorized("admins only")
      {:unauthorized, "admins only"}
  """
  @spec unauthorized(msg :: String.t()) :: {:unauthorized, msg :: String.t()}
  def unauthorized(msg), do: {:unauthorized, msg}

  @doc """
  Builds a validation-error response wrapping the (invalid) `request`,
  typically an `Ecto.Changeset`.

  ## Examples

      iex> X3m.System.Response.validation_error(%{valid?: false})
      {:validation_error, %{valid?: false}}
  """
  @spec validation_error(request :: map) :: {:validation_error, request :: map}
  def validation_error(request),
    do: {:validation_error, request}

  @doc """
  Builds a response signalling that the request is missing the aggregate id
  expected under `id_field`.

  ## Examples

      iex> X3m.System.Response.missing_id("id")
      {:missing_id, "id"}
  """
  @spec missing_id(id_field :: atom | String.t()) :: {:missing_id, id_field :: atom | String.t()}
  def missing_id(id_field),
    do: {:missing_id, id_field}

  @doc """
  Builds a generic error response wrapping `reason`.

  ## Examples

      iex> X3m.System.Response.error(:not_found)
      {:error, :not_found}
  """
  @spec error(reason :: any) :: {:error, reason :: any}
  def error(any),
    do: {:error, any}
end
