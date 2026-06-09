# X3m.System

[![Build Status](https://github.com/x3m-ex/system/actions/workflows/bless.yml/badge.svg)](https://github.com/x3m-ex/system/actions/workflows/bless.yml)
[![Hex version](https://img.shields.io/hexpm/v/x3m_system.svg "Hex version")](https://hex.pm/packages/x3m_system)
[![Coverage Status](https://coveralls.io/repos/github/x3m-ex/system/badge.svg)](https://coveralls.io/github/x3m-ex/system)

Building blocks for distributed and/or CQRS/ES systems in Elixir.

`X3m.System` gives you a small set of composable pieces for building message-driven
backends: a **message** that carries a request and its response, a **router** that
registers services across a cluster, a **dispatcher** that finds a node offering a
service and waits for the reply, and — when you need it — **aggregates** with event
sourcing and a backend-agnostic **scheduler** for delivering messages in the future.

The pieces are **à la carte**. You can use the messaging layer (message + router +
dispatcher) on its own, add aggregates and event sourcing only where you need them,
and use the scheduler independently of everything else.

## Installation

```elixir
def deps do
  [
    {:x3m_system, "~> 0.9.1"}
  ]
end
```

Two dependencies are optional and only needed for some building blocks:

- `:elixir_uuid` — needed when working with aggregates (id generation).
- `:tzdata` — needed for `X3m.System.Scheduler`.

## A minimal example

Define a router that registers a service and the module that handles it:

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

Register the services (typically from your application's `start/2`) and dispatch a
message to the service by name:

```elixir
:ok = MyApp.Router.register_services()

:greet
|> X3m.System.Message.new(raw_request: %{"name" => "Ada"})
|> X3m.System.Dispatcher.dispatch()
#=> %X3m.System.Message{response: {:ok, "Hello, Ada!"}, ...}
```

No aggregates or event store are involved here — any module registered through a
router can be a dispatch target.

## Guides

- [Getting started](guides/getting-started.md) — install, optional deps, your first dispatch.
- [Messaging](guides/messaging.md) — `Message`, `Router`, `Dispatcher` and the response shapes.
- [Aggregates & event sourcing](guides/aggregates-and-event-sourcing.md) — `Aggregate`, `MessageHandler`, persisting events, snapshotting and supervision.
- [Distribution](guides/distribution.md) — service discovery across nodes, choosing the node, and forwarding.
- [Scheduling](guides/scheduling.md) — persistable, future-dated message delivery with `Scheduler`.

## License

Released under the MIT License. See the [LICENSE](https://github.com/x3m-ex/system/blob/master/LICENSE) file.
