# Telemetry

x3m_system emits [`:telemetry`](https://hexdocs.pm/telemetry) events under the
`[:x3m, :system, name]` prefix. Attach to them to build metrics, traces or logs:

```elixir
:telemetry.attach(
  "my-app-x3m-service-responded",
  [:x3m, :system, :service_responded],
  &MyApp.Metrics.handle_event/4,
  nil
)
```

## Units

- `duration` is in **native** time units: the difference of two
  `System.monotonic_time/0` readings. Convert it before you record it, e.g.
  `System.convert_time_unit(duration, :native, :millisecond)`.
- `mono_start` is a `System.monotonic_time/0` reading, also in native units.
- `start` and `time` are UTC `DateTime`s.
- `timeout_after` is in milliseconds.

## Dispatcher (caller node)

A `dispatch/2` emits `:discovering_service` and then either `:service_not_found`, or
`:service_found`, `:invoking_service` and `:service_responded` for each node it tries.
`service_node` is `:local` or the name of the provider node.

| event | measurements | metadata |
|---|---|---|
| `:discovering_service` | `start`, `mono_start` | `message`, `caller_node` |
| `:service_not_found` | `time`, `duration` (since dispatch start) | `message`, `caller_node` |
| `:service_found` | `time`, `duration` (since dispatch start) | `message`, `caller_node`, `service_node` |
| `:invoking_service` | `start`, `mono_start` | `message`, `caller_node`, `service_node` |
| `:service_responded` | `time`, `duration` (since `:invoking_service`) | `message`, `caller_node`, `service_node` |
| `:checking_if_service_call_is_authorized` | `start`, `mono_start` | `message`, `caller_node` |

In `:service_responded`, `message.response` holds the result, which may be a timeout
or an error. Its `duration` is what the caller waited.

## Router (provider node)

| event | measurements | metadata |
|---|---|---|
| `:service_request_received` | none | `service`, `visibility` (`:public` or `:private`), `origin_node` |
| `:executing_service` | `start`, `mono_start` | `node`, `service` |
| `:execution_finished` | `time`, `duration` (since `:executing_service`) | `message` |
| `:register_local_services` | none | `public`, `private` (maps of service => router) |

`:execution_finished` is emitted only when the handler replies with `{:reply, message}`.
Its `duration` covers the handler call and the send of the reply. It does not include
the network, or any time the caller spent waiting.

## Aggregates

| event | measurements | metadata |
|---|---|---|
| `:new_aggr_spawned` | none | `id` |
| `:handle_msg` | none | `aggregate`, `message` (the handler name) |
| `:aggregate_commit_timeout` | `timeout_after` | `aggregate`, `message` |

## Cluster

| event | measurements | metadata |
|---|---|---|
| `:node_joined` | none | `node` |
| `:node_left` | none | `node` |

x3m_system itself handles `:register_local_services`, `:node_joined` and `:node_left` to
keep its service registry current, so attach to them only to observe them.

The `message` in metadata is the full `X3m.System.Message`, including the request, so
don't log it wholesale.
