defmodule X3m.System.RouterTest do
  use ExUnit.Case, async: true

  alias X3m.System.Test.Router

  describe "get registered services" do
    test "public" do
      assert [first: 1, unauthorized_service: 1, custom_unauthorized_service: 1] =
               Router.registered_services(:public)
    end

    test "private" do
      assert([private_service: 1] = Router.registered_services(:private))
    end

    test "all" do
      assert [
               private_service: 1,
               first: 1,
               unauthorized_service: 1,
               custom_unauthorized_service: 1
             ] = Router.registered_services(:all)
    end
  end
end
