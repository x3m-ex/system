defmodule X3m.System.Test.NonOkService do
  @moduledoc !"""
             Service provider used only by the distributed tests. Router-generated service
             functions always return `:ok`, so this module registers itself directly to provide
             services that return anything else.
             """

  alias X3m.System.Instrumenter
  alias X3m.System.Message

  @doc "Registers this module's services as public services provided by this node."
  @spec register_services :: :ok
  def register_services do
    services = Map.new([:not_ok, :handler_tuple, :badrpc_tuple], &{&1, __MODULE__})
    Instrumenter.execute(:register_local_services, %{}, %{public: services, private: %{}})

    :ok
  end

  @doc "Returns a value other than `:ok`, which no Router-generated service does."
  @spec not_ok(Message.t()) :: :not_ok
  def not_ok(%Message{}), do: :not_ok

  @doc "Returns a tuple shaped like the dispatcher's internal local-handler result."
  @spec handler_tuple(Message.t()) :: {:handler, :not_a_monitor}
  def handler_tuple(%Message{}), do: {:handler, :not_a_monitor}

  @doc "Returns a tuple shaped like a failed remote call."
  @spec badrpc_tuple(Message.t()) :: {:badrpc, :not_a_failure}
  def badrpc_tuple(%Message{}), do: {:badrpc, :not_a_failure}
end
