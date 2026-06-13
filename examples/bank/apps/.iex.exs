defmodule BankingClusterBoot do
  @moduledoc false

  def connect_to_peers do
    {:ok, hostname} = :inet.gethostname()
    self_node = Node.self()

    peers =
      [:banking_core_1, :banking_listeners_1, :banking_api_1]
      |> Enum.map(&:"#{&1}@#{hostname}")
      |> Enum.reject(&(&1 == self_node))

    _wait_for_peers(peers, _attempts = 30)
  end

  defp _wait_for_peers(_peers, 0) do
    IO.puts("[cluster] timed out waiting for peers; Node.list/0 = #{inspect(Node.list())}")
  end

  defp _wait_for_peers(peers, attempts) do
    connected =
      peers
      |> Enum.filter(&(Node.connect(&1) == true))

    if connected != [] do
      IO.puts("[cluster] connected to #{inspect(connected)}; Node.list/0 = #{inspect(Node.list())}")
    else
      Process.sleep(500)
      _wait_for_peers(peers, attempts - 1)
    end
  end
end

spawn(fn -> BankingClusterBoot.connect_to_peers() end)
