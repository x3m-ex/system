defmodule Banking.Api.Router do
  @moduledoc !"""
             HTTP router — Plug.Router with all account endpoints.
             """
  use Plug.Router
  alias Banking.Api.ServiceInvoker

  plug Plug.RequestId
  plug Plug.Logger
  plug :match

  plug Plug.Parsers,
    parsers: [:json],
    json_decoder: Jason

  plug :dispatch

  # Commands
  post "/accounts" do
    ServiceInvoker.invoke(conn, :open_account, conn.body_params)
  end

  put "/accounts/:id/deposit" do
    conn.body_params
    |> Map.put("id", id)
    |> then(&ServiceInvoker.invoke(conn, :deposit, &1))
  end

  put "/accounts/:id/withdraw" do
    conn.body_params
    |> Map.put("id", id)
    |> then(&ServiceInvoker.invoke(conn, :withdraw, &1))
  end

  put "/accounts/:id/close" do
    conn.body_params
    |> Map.put("id", id)
    |> then(&ServiceInvoker.invoke(conn, :close_account, &1))
  end

  # Queries
  get "/accounts/:id" do
    ServiceInvoker.invoke(conn, :get_account, %{"id" => id})
  end

  get "/accounts" do
    ServiceInvoker.invoke(conn, :list_accounts, conn.query_params)
  end

  match _ do
    conn
    |> put_resp_content_type("application/json")
    |> send_resp(404, Jason.encode!(%{error: "not_found"}))
  end
end
