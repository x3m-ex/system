defmodule Banking.Api.ServiceInvokerTest do
  use ExUnit.Case, async: true

  alias Banking.Api.ServiceInvoker

  describe "conflicts" do
    test "a stale aggregate version answers 409" do
      conn = _invoke({:error, :wrong_expected_version, 3})

      assert 409 == conn.status
      assert %{"error" => "aggregate version conflict"} == Jason.decode!(conn.resp_body)
    end

    test "creating an aggregate that is already running answers 409" do
      conn = _invoke({:error, :key_already_registered, self()})

      assert 409 == conn.status
      assert %{"error" => "aggregate already exists"} == Jason.decode!(conn.resp_body)
    end
  end

  defp _invoke(response) do
    :post
    |> Plug.Test.conn("/")
    |> ServiceInvoker.invoke(:respond_with, %{"response" => response})
  end
end
