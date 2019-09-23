defmodule X3m.System.Response do
  @type t ::
          :ok
          | {:ok, any}
          | {:created, any}
          | {:service_unavailable, atom}
          | {:service_timeout, atom, String.t(), non_neg_integer}
          | {:validation_error, map}
          | {:missing_id, atom | String.t()}
          | {:error, any}

  @spec ok() :: :ok
  def ok, do: :ok

  @spec ok(any) :: {:ok, any}
  def ok(payload), do: {:ok, payload}

  @spec created(any) :: {:created, any}
  def created(id), do: {:created, id}

  @spec service_unavailable(atom) :: {:service_unavailable, atom}
  def service_unavailable(msg_name), do: {:service_unavailable, msg_name}

  @spec service_timeout(atom, String.t(), non_neg_integer) ::
          {:service_timeout, atom, String.t(), non_neg_integer}
  def service_timeout(msg_name, req_id, timeout),
    do: {:service_timeout, msg_name, req_id, timeout}

  @spec unauthorized(String.t()) :: {:unauthorized, String.t()}
  def unauthorized(msg), do: {:unauthorized, msg}

  @spec validation_error(map) :: {:validation_error, map}
  def validation_error(request),
    do: {:validation_error, request}

  @spec missing_id(atom | String.t()) :: {:missing_id, atom | String.t()}
  def missing_id(id_field),
    do: {:missing_id, id_field}

  @spec error(any) :: {:error, any}
  def error(any),
    do: {:error, any}
end
