# Getting started

`X3m.System` is a set of building blocks for message-driven Elixir backends. This
guide gets you from an empty project to dispatching your first message. It uses only
the messaging layer — no aggregates or event store required.

## Install

Add the dependency:

```elixir
def deps do
  [
    {:x3m_system, "~> 0.9"}
  ]
end
```

Two dependencies are optional and pulled in only for specific building blocks:

- `:elixir_uuid` — id generation when working with [aggregates](aggregates-and-event-sourcing.md).
- `:tzdata` — required by the [scheduler](scheduling.md).

`X3m.System` starts its own OTP application (a task supervisor, a node monitor and the
service registry), so once it is a dependency there is nothing to add to your
supervision tree to use the messaging layer.

## The three core pieces

- `X3m.System.Message` — the struct that flows through the system. It carries the
  service name, the raw request, shared `assigns`, and — once handled — a `response`.
- `X3m.System.Router` — registers **services** (named entry points) and maps each to a
  module/function that handles it.
- `X3m.System.Dispatcher` — given a message, finds a node offering its service, invokes
  it, and returns the message with its `response` set.

## Your first service

Define a router and a handler module:

```elixir
defmodule MyApp.Router do
  use X3m.System.Router

  service :greet, MyApp.Greeter

  def authorize(_message), do: :ok
end

defmodule MyApp.Greeter do
  alias X3m.System.Message

  def greet(%Message{} = message) do
    name = message.raw_request["name"]
    {:reply, Message.ok(message, "Hello, #{name}!")}
  end
end
```

A few things to note:

- `service :greet, MyApp.Greeter` registers the `:greet` service and routes it to
  `MyApp.Greeter.greet/1` (same name). Use the three-argument form
  `service :greet, MyApp.Greeter, :handle_greet` to call a differently named function.
- A handler returns `{:reply, message}` to send the message back to the caller, or
  `:noreply` to stay silent.
- `authorize/1` runs before the handler. Returning `:ok` lets the call through;
  anything else becomes the response. The default (if you don't define it) denies
  everything, so you always define it explicitly.

## Register and dispatch

Services are announced to the registry at runtime — usually from your application's
`start/2`:

```elixir
:ok = MyApp.Router.register_services()
```

Then build a message and dispatch it:

```elixir
:greet
|> X3m.System.Message.new(raw_request: %{"name" => "Ada"})
|> X3m.System.Dispatcher.dispatch()
#=> %X3m.System.Message{response: {:ok, "Hello, Ada!"}, ...}
```

`dispatch/2` blocks until the handler replies (default timeout 5s) and returns the
resolved message. Pattern-match on its `response` — see `X3m.System.Response` for the
full vocabulary of response shapes.

## Where to go next

- [Messaging](messaging.md) — the full message lifecycle, routers and responses.
- [Aggregates & event sourcing](aggregates-and-event-sourcing.md) — model state with
  events.
- [Distribution](distribution.md) — run services across a cluster.
- [Scheduling](scheduling.md) — deliver messages in the future.
