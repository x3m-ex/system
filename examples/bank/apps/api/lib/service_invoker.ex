defmodule Banking.Api.ServiceInvoker do
  @moduledoc !"""
             Builds an X3m.System.Message from an HTTP request, dispatches it,
             and sends the JSON response.
             """
  alias X3m.System.Message, as: SysMsg
  alias X3m.System.Dispatcher
  alias Banking.Identity
  alias Plug.Conn

  @spec invoke(conn :: Conn.t(), service_name :: atom(), params :: map()) :: Conn.t()
  def invoke(%Conn{} = conn, service_name, params) do
    req_id =
      conn
      |> Conn.get_resp_header("x-request-id")
      |> List.first()

    identity = _build_identity(params)
    raw_request = Map.delete(params, "invoked_by")

    service_name
    |> SysMsg.new(raw_request: raw_request, id: req_id)
    |> SysMsg.assign(:invoked_by, identity)
    |> Dispatcher.dispatch()
    |> _respond(conn)
  end

  defp _build_identity(%{"invoked_by" => %{"user_id" => uid} = invoked_by}) do
    %Identity{
      user_id: uid,
      admin?: Map.get(invoked_by, "admin?", false)
    }
  end

  defp _build_identity(%{"invoked_by" => %{"admin?" => true}}) do
    %Identity{admin?: true}
  end

  defp _build_identity(%{"admin" => "true"}), do: %Identity{admin?: true}

  defp _build_identity(_), do: %Identity{}

  # Success

  defp _respond(%SysMsg{response: {:created, id, _version}}, conn),
    do: _json(conn, 201, %{id: id})

  defp _respond(%SysMsg{response: {:ok, version}}, conn) when is_integer(version) do
    conn
    |> Conn.put_resp_content_type("application/json")
    |> Conn.send_resp(204, "")
  end

  defp _respond(%SysMsg{response: {:ok, data}}, conn),
    do: _json(conn, 200, data)

  # Validation

  defp _respond(%SysMsg{response: {:validation_error, changeset}}, conn) do
    errors = Banking.ErrorHelpers.traverse_errors(changeset)
    _json(conn, 422, %{errors: errors})
  end

  # Domain errors

  defp _respond(%SysMsg{response: {:error, :not_found}}, conn),
    do: _json(conn, 404, %{error: "not_found"})

  defp _respond(%SysMsg{response: {:error, :forbidden}}, conn),
    do: _json(conn, 403, %{error: "forbidden"})

  defp _respond(%SysMsg{response: {:error, {:conflict, message}}}, conn),
    do: _json(conn, 409, %{error: message})

  defp _respond(%SysMsg{response: {:error, :key_already_registered, _}}, conn),
    do: _json(conn, 409, %{error: "aggregate already exists"})

  defp _respond(%SysMsg{response: {:error, {:error, :wrong_expected_version, _}}}, conn),
    do: _json(conn, 409, %{error: "aggregate already exists"})

  defp _respond(%SysMsg{response: {:error, reason}}, conn) when is_atom(reason),
    do: _json(conn, 422, %{error: to_string(reason)})

  defp _respond(%SysMsg{response: {:error, reason}}, conn),
    do: _json(conn, 422, %{error: inspect(reason)})

  # Infrastructure

  defp _respond(%SysMsg{response: {:service_unavailable, _}}, conn),
    do: _json(conn, 503, %{error: "service_unavailable"})

  defp _respond(%SysMsg{halted?: true, response: response}, conn),
    do: _json(conn, 422, %{error: inspect(response)})

  defp _json(conn, status, body) do
    conn
    |> Conn.put_resp_content_type("application/json")
    |> Conn.send_resp(status, Jason.encode!(body))
  end
end
