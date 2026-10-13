defmodule X3m.System.Test.ProbeScheduler do
  @moduledoc "Scheduler whose store and responses are injected per test, on a 50ms interval."
  use X3m.System.Scheduler
  alias X3m.System.Message, as: SysMsg

  @type probe :: %{
          test_pid: pid(),
          save: (SysMsg.t() -> :ok | {:ok, SysMsg.t()} | {:error, reason :: term()}),
          load: (nil | DateTime.t(), DateTime.t() -> {:ok, [SysMsg.t()]} | {:error, term()}),
          respond: (SysMsg.t() -> :ok | {:retry, non_neg_integer(), SysMsg.t()})
        }

  @interval_ms 50

  @doc "The interval this scheduler reloads alarms on."
  @spec interval_ms() :: milliseconds :: pos_integer()
  def interval_ms, do: @interval_ms

  @impl X3m.System.Scheduler
  @spec save_alarm(SysMsg.t(), aggregate_id :: String.t(), probe()) ::
          :ok | {:ok, SysMsg.t()} | {:error, reason :: term()}
  def save_alarm(%SysMsg{} = msg, _aggregate_id, %{save: save}),
    do: save.(msg)

  @impl X3m.System.Scheduler
  @spec load_alarms(load_from :: nil | DateTime.t(), load_until :: DateTime.t(), probe()) ::
          {:ok, [SysMsg.t()]} | {:error, term()}
  def load_alarms(from, until, %{test_pid: test_pid, load: load}) do
    send(test_pid, {:load_alarms, from, until, DateTime.utc_now()})
    load.(from, until)
  end

  @impl X3m.System.Scheduler
  @spec service_responded(SysMsg.t(), probe()) ::
          :ok | {:retry, non_neg_integer(), SysMsg.t()}
  def service_responded(%SysMsg{} = msg, %{test_pid: test_pid, respond: respond}) do
    send(test_pid, {:service_responded, msg, self()})
    respond.(msg)
  end

  @impl X3m.System.Scheduler
  def in_memory_interval, do: @interval_ms
end
