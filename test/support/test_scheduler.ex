defmodule X3m.System.Test.Scheduler do
  use X3m.System.Scheduler
  alias X3m.System.Message, as: SysMsg

  @impl X3m.System.Scheduler
  @spec save_alarm(SysMsg.t(), String.t(), pid()) :: {:ok, SysMsg.t()}
  def save_alarm(%SysMsg{} = msg, aggregate_id, test_pid) do
    msg = SysMsg.assign(msg, :injected_value, __MODULE__)
    send(test_pid, {:save_alarm, msg, aggregate_id})
    {:ok, msg}
  end

  @impl X3m.System.Scheduler
  @spec load_alarms(load_from :: nil | DateTime.t(), load_until :: DateTime.t(), pid()) ::
          {:ok, [SysMsg.t()]}
          | {:error, term()}
  def load_alarms(from, until, test_pid) do
    send(test_pid, {:load_alarms, from, until})
    alarms = []
    {:ok, alarms}
  end

  @impl X3m.System.Scheduler
  @spec service_responded(SysMsg.t(), pid()) ::
          :ok
          | {:retry, non_neg_integer(), SysMsg.t()}
  def service_responded(%SysMsg{} = msg, test_pid) do
    send(test_pid, {:service_responded, msg})

    case msg do
      %SysMsg{assigns: %{redelivered?: true}} -> :ok
      %SysMsg{} -> {:retry, 50, SysMsg.assign(msg, :redelivered?, true)}
    end
  end

  @impl X3m.System.Scheduler
  def in_memory_interval,
    do: 2 * 60 * 1_000
end
