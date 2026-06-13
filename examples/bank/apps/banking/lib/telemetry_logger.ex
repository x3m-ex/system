defmodule Banking.TelemetryLogger do
  @moduledoc !"""
  Attaches to x3m_system telemetry events and logs them.
  """
  require Logger

  @spec setup() :: :ok
  def setup do
    events = [
      # cluster
      [:x3m, :system, :node_joined],
      [:x3m, :system, :node_left],

      # service discovery + dispatch
      [:x3m, :system, :discovering_service],
      [:x3m, :system, :service_found],
      [:x3m, :system, :service_not_found],
      [:x3m, :system, :service_request_received],
      [:x3m, :system, :invoking_service],
      [:x3m, :system, :service_responded],
      [:x3m, :system, :executing_service],
      [:x3m, :system, :execution_finished],

      # aggregate
      [:x3m, :system, :handle_msg],
      [:x3m, :system, :new_aggr_spawned],
      [:x3m, :system, :aggregate_commit_timeout]
    ]

    :telemetry.attach_many("banking-logger", events, &__MODULE__.handle_event/4, nil)
    :ok
  end

  # Cluster

  def handle_event([:x3m, :system, :node_joined], _, %{node: node}, _),
    do: Logger.info(fn -> "[Node] #{node} joined" end)

  def handle_event([:x3m, :system, :node_left], _, %{node: node}, _),
    do: Logger.info(fn -> "[Node] #{node} left" end)

  # Service discovery + dispatch

  def handle_event([:x3m, :system, :discovering_service], _, %{message: msg}, _),
    do: Logger.debug(fn -> "[Dispatch] Discovering #{msg.service_name}" end)

  def handle_event([:x3m, :system, :service_found], measurements, %{message: msg, service_node: node}, _) do
    duration = _format_duration(measurements[:duration])
    Logger.debug(fn -> "[Dispatch] #{msg.service_name} found on #{node} in #{duration}" end)
  end

  def handle_event([:x3m, :system, :service_not_found], measurements, %{message: msg}, _) do
    duration = _format_duration(measurements[:duration])
    Logger.warning(fn -> "[Dispatch] #{msg.service_name} not found in #{duration}" end)
  end

  def handle_event([:x3m, :system, :invoking_service], _, %{message: msg, service_node: node}, _),
    do: Logger.info(fn -> "[Dispatch] Invoking #{msg.service_name} on #{node}" end)

  def handle_event([:x3m, :system, :service_responded], measurements, %{message: msg}, _) do
    duration = _format_duration(measurements[:duration])
    Logger.info(fn -> "[Dispatch] #{msg.service_name} responded in #{duration}" end)
  end

  # Service execution (on the receiving node)

  def handle_event([:x3m, :system, :service_request_received], _, %{service: service, origin_node: origin}, _),
    do: Logger.info(fn -> "[Service] Received #{service} from #{origin}" end)

  def handle_event([:x3m, :system, :executing_service], _, %{service: service}, _),
    do: Logger.debug(fn -> "[Service] Executing #{service}" end)

  def handle_event([:x3m, :system, :execution_finished], measurements, %{message: msg}, _) do
    duration = _format_duration(measurements[:duration])
    Logger.info(fn -> "[Service] #{msg.service_name} finished in #{duration}" end)
  end

  # Aggregate

  def handle_event([:x3m, :system, :handle_msg], _, %{aggregate: aggregate, message: message}, _),
    do: Logger.info(fn -> "[Aggregate] Handling #{inspect(message)} on #{inspect(aggregate)}" end)

  def handle_event([:x3m, :system, :new_aggr_spawned], _, %{id: id}, _),
    do: Logger.info(fn -> "[Aggregate] New process spawned for #{id}" end)

  def handle_event(
        [:x3m, :system, :aggregate_commit_timeout],
        %{timeout_after: timeout},
        %{aggregate: aggregate, message: message},
        _
      ),
      do:
        Logger.error(fn ->
          "[Aggregate] Commit timeout for #{inspect(aggregate)}.#{inspect(message)} after #{timeout}ms"
        end)

  # Duration formatting

  defp _format_duration(nil), do: "?"

  defp _format_duration(duration) do
    cond do
      duration < 1_000 ->
        "#{duration}ns"

      duration < 1_000_000 ->
        duration
        |> System.convert_time_unit(:native, :microsecond)
        |> then(&"#{&1}µs")

      true ->
        duration
        |> System.convert_time_unit(:native, :millisecond)
        |> then(&"#{&1}ms")
    end
  end
end
