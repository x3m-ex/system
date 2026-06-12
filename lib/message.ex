defmodule X3m.System.Message do
  @moduledoc """
  System Message.

  This module defines a `X3m.System.Message` struct and the main functions
  for working with it.

  ## Fields:

    * `service_name` - the name of the service that should handle this message. Example: `:create_job`.
    * `id` - unique id of the message.
    * `correlation_id` - id of the message that "started" conversation.
    * `causation_id` - id of the message that "caused" this message.
    * `logger_metadata` - In each new process `Logger.metadata` should be set to this value.
    * `invoked_at` - utc time when message was generated.
    * `dry_run` - specifies dry run option. It can be either `false`, `true` or `:verbose`.
    * `request` - request structure converted to Ecto.Changeset (or anything else useful).
    * `raw_request` - request as it is received before converting to Message (i.e. `params` from controller action).
    * `assigns` - shared Data as a map.
    * `response` - the response for invoker.
    * `events` - list of generated events.
    * `aggregate_meta` - metadata for aggregate.
    * `valid?` - `true` by default on a new message; set to `false` by `put_request/2`
      when the structured request fails validation. It means "not known to be invalid"
      rather than "already validated".
    * `origin_node` - Node.self() of invoker
    * `reply_to` - Pid of process that is waiting for response.
    * `halted?` - when set to `true` it means that response should be returned to the invoker
      without further processing of Message.
  """
  alias X3m.System.Response

  @enforce_keys ~w(service_name id correlation_id causation_id invoked_at dry_run
                   origin_node reply_to halted? raw_request request valid? response events
                   aggregate_meta assigns logger_metadata)a
  defstruct @enforce_keys

  @type t() :: %__MODULE__{
          service_name: atom,
          id: String.t(),
          correlation_id: String.t(),
          causation_id: String.t(),
          logger_metadata: Keyword.t(),
          invoked_at: DateTime.t(),
          dry_run: dry_run(),
          raw_request: map(),
          request: nil | request,
          valid?: boolean,
          assigns: assigns,
          response: nil | Response.t(),
          events: [map],
          aggregate_meta: map,
          origin_node: Node.t(),
          reply_to: pid,
          halted?: boolean
        }
  @typep assigns :: %{atom => any}
  @typep request :: map()
  @type error :: {String.t(), Keyword.t()}
  @type errors :: [{atom, error}]
  @type dry_run :: boolean | :verbose

  @doc """
  Creates new message with given `service_name` and provided `opts`:

    * `id` - id of the message. If not provided it generates random one.
    * `correlation_id` - id of "conversation". If not provided it is set to `id`.
    * `causation_id` - id of message that "caused" this message. If not provided it is set to `id`.
    * `reply_to` - sets pid of process that expects response. If not provided it is set to `self()`.
    * `raw_request` - sets raw request as it is received (i.e. `params` from controller action).
    * `logger_metadata` - if not provided `Logger.metadata` is used by default.

  ## Examples

      iex> msg = X3m.System.Message.new(:open_account, raw_request: %{"id" => "acc-1"})
      iex> {msg.service_name, msg.raw_request, msg.valid?, msg.halted?}
      {:open_account, %{"id" => "acc-1"}, true, false}
      iex> msg.correlation_id == msg.id and msg.causation_id == msg.id
      true
  """
  @spec new(atom, Keyword.t()) :: __MODULE__.t()
  def new(service_name, opts \\ []) when is_atom(service_name) do
    id = Keyword.get(opts, :id) || gen_msg_id()
    correlation_id = Keyword.get(opts, :correlation_id, id)
    causation_id = Keyword.get(opts, :causation_id, correlation_id)
    dry_run = Keyword.get(opts, :dry_run, false)
    reply_to = Keyword.get(opts, :reply_to, self())
    raw_request = Keyword.get(opts, :raw_request)
    logger_metadata = Keyword.get(opts, :logger_metadata, Logger.metadata())

    %__MODULE__{
      service_name: service_name,
      id: id,
      correlation_id: correlation_id,
      causation_id: causation_id,
      invoked_at: DateTime.utc_now(),
      dry_run: dry_run,
      raw_request: raw_request,
      request: nil,
      valid?: true,
      response: nil,
      events: [],
      aggregate_meta: %{},
      origin_node: Node.self(),
      reply_to: reply_to,
      halted?: false,
      assigns: %{},
      logger_metadata: logger_metadata
    }
  end

  @doc """
  Creates new message with given `service_name` that is caused by other `msg`.

  The child keeps the parent's `correlation_id` (the id of the message that *started*
  the conversation) and sets its `causation_id` to the parent's `id`.

  ## Examples

      iex> parent = X3m.System.Message.new(:open_account)
      iex> child = X3m.System.Message.new_caused_by(:notify_owner, parent)
      iex> {child.service_name, child.correlation_id == parent.correlation_id, child.causation_id == parent.id}
      {:notify_owner, true, true}
      iex> child.id == parent.id
      false
  """
  @spec new_caused_by(atom, __MODULE__.t(), Keyword.t()) :: __MODULE__.t()
  def new_caused_by(service_name, %__MODULE__{} = msg, opts \\ []) when is_atom(service_name) do
    service_name
    |> new(
      id: gen_msg_id(),
      correlation_id: msg.correlation_id,
      causation_id: msg.id,
      raw_request: opts[:raw_request]
    )
  end

  @doc """
  Returns `sys_msg` re-targeted at a different `service_name`, leaving its ids,
  payload and assigns intact. Useful for re-dispatching the same request to another
  service.

  ## Examples

      iex> msg = X3m.System.Message.new(:open_account, id: "m-1", raw_request: %{"id" => "acc-1"})
      iex> retargeted = X3m.System.Message.to_service(msg, :close_account)
      iex> {retargeted.service_name, retargeted.id, retargeted.raw_request}
      {:close_account, "m-1", %{"id" => "acc-1"}}
  """
  @spec to_service(t(), service_name :: atom) :: t()
  def to_service(%__MODULE__{} = sys_msg, service_name),
    do: %__MODULE__{sys_msg | service_name: service_name}

  @doc """
  Assigns a value to a key in the message.
  The "assigns" storage is meant to be used to store values in the message
  so that others in pipeline can use them when needed. The assigns storage
  is a map.

  ## Examples

      iex> sys_msg = X3m.System.Message.new(:create_user)
      iex> sys_msg.assigns[:user_id]
      nil
      iex> sys_msg = X3m.System.Message.assign(sys_msg, :user_id, 123)
      iex> sys_msg.assigns[:user_id]
      123
  """
  @spec assign(__MODULE__.t(), atom, any) :: __MODULE__.t()
  def assign(%__MODULE__{assigns: assigns} = sys_msg, key, val) when is_atom(key),
    do: %{sys_msg | assigns: Map.put(assigns, key, val)}

  @doc """
  Returns `sys_msg` with provided `response` and as `halted? = true`.

  Events accumulated with `add_event/2` are reversed back into the order they were
  added.

  ## Examples

      iex> alias X3m.System.{Message, Response}
      iex> msg = Message.new(:open_account) |> Message.add_event(:opened) |> Message.add_event(:limit_set)
      iex> returned = Message.return(msg, Response.ok(:done))
      iex> {returned.response, returned.halted?, returned.events}
      {{:ok, :done}, true, [:opened, :limit_set]}
  """
  @spec return(__MODULE__.t(), Response.t()) :: __MODULE__.t()
  def return(%__MODULE__{events: events} = sys_msg, response) do
    sys_msg
    |> Map.put(:response, response)
    |> Map.put(:halted?, true)
    |> Map.put(:events, Enum.reverse(events))
  end

  @doc """
  Returns `message` it received with `Response.created(id)` result set.

  ## Examples

      iex> msg = X3m.System.Message.new(:open_account) |> X3m.System.Message.created("acc-1")
      iex> {msg.response, msg.halted?}
      {{:created, "acc-1"}, true}
  """
  @spec created(__MODULE__.t(), any) :: __MODULE__.t()
  def created(%__MODULE__{} = message, id) do
    response = Response.created(id)
    return(message, response)
  end

  @doc """
  Returns `message` carrying `Response.ok/0`'s bare `:ok` result, with `halted? = true`.

  ## Examples

      iex> msg = X3m.System.Message.new(:ping) |> X3m.System.Message.ok()
      iex> {msg.response, msg.halted?}
      {:ok, true}
  """
  @spec ok(__MODULE__.t()) :: __MODULE__.t()
  def ok(message) do
    response = Response.ok()
    return(message, response)
  end

  @doc """
  Returns `message` with a `Response.ok/1` result wrapping the given value, with
  `halted? = true`.

  ## Examples

      iex> msg = X3m.System.Message.new(:get_account) |> X3m.System.Message.ok(%{balance: 10})
      iex> {msg.response, msg.halted?}
      {{:ok, %{balance: 10}}, true}
  """
  @spec ok(__MODULE__.t(), any) :: __MODULE__.t()
  def ok(message, any) do
    response = Response.ok(any)
    return(message, response)
  end

  @doc """
  Returns `message` with a `Response.error/1` result wrapping the given reason, with
  `halted? = true`.

  ## Examples

      iex> msg = X3m.System.Message.new(:open_account) |> X3m.System.Message.error(:not_found)
      iex> {msg.response, msg.halted?}
      {{:error, :not_found}, true}
  """
  @spec error(__MODULE__.t(), any) :: __MODULE__.t()
  def error(message, any) do
    response = Response.error(any)
    return(message, response)
  end

  @doc """
  Stores a validated `request` (e.g. an `Ecto.Changeset` or a command struct) on the
  `message`.

  If `request` carries `valid?: false`, the message is halted with a
  `Response.validation_error/1` so dispatch returns the error immediately. Otherwise
  the request is stored and `message.valid?` is set to `true`.

  ## Examples

  A valid request is stored and the message stays open:

      iex> msg = X3m.System.Message.new(:open_account)
      iex> msg = X3m.System.Message.put_request(%{owner: "Ada"}, msg)
      iex> {msg.valid?, msg.request, msg.halted?}
      {true, %{owner: "Ada"}, false}

  An invalid request (e.g. an invalid `Ecto.Changeset`) halts with a validation error:

      iex> msg = X3m.System.Message.new(:open_account)
      iex> msg = X3m.System.Message.put_request(%{valid?: false}, msg)
      iex> {msg.valid?, msg.halted?, msg.response}
      {false, true, {:validation_error, %{valid?: false}}}
  """
  @spec put_request(request :: map(), t()) :: t()
  def put_request(%{valid?: false} = request, %__MODULE__{} = message) do
    %{message | valid?: false, request: request}
    |> return(Response.validation_error(request))
  end

  def put_request(%{} = request, %__MODULE__{} = message),
    do: %{message | valid?: true, request: request}

  @doc """
  Puts `value` under `key` in `message.raw_request` map.

  ## Examples

      iex> msg = X3m.System.Message.new(:open_account, raw_request: %{"id" => "acc-1"})
      iex> X3m.System.Message.put_in_raw_request(msg, "owner", "Ada").raw_request
      %{"id" => "acc-1", "owner" => "Ada"}

  When `raw_request` is `nil` it is treated as an empty map:

      iex> msg = X3m.System.Message.new(:open_account)
      iex> X3m.System.Message.put_in_raw_request(msg, :owner, "Ada").raw_request
      %{owner: "Ada"}
  """
  @spec put_in_raw_request(t(), key :: term(), value :: term()) :: t()
  def put_in_raw_request(%__MODULE__{} = message, key, value) do
    raw_request =
      (message.raw_request || %{})
      |> Map.put(key, value)

    %{message | raw_request: raw_request}
  end

  @doc """
  Adds `event` in `message.events` list. If `event` is nil
  it behaves as noop.

  After `return/2` (and friends) order of `msg.events` will be the same as
  they've been added.

  ## Examples

  Events are prepended, so they accumulate in reverse-insertion order until `return/2`
  reverses them back into the order they were added:

      iex> msg = X3m.System.Message.new(:open_account)
      iex> msg = msg |> X3m.System.Message.add_event(:opened) |> X3m.System.Message.add_event(:limit_set)
      iex> msg.events
      [:limit_set, :opened]

  A `nil` event is ignored:

      iex> msg = X3m.System.Message.new(:open_account)
      iex> X3m.System.Message.add_event(msg, nil).events
      []
  """
  @spec add_event(message :: t(), event :: nil | any) :: t()
  def add_event(%__MODULE__{} = message, nil),
    do: message

  def add_event(%__MODULE__{events: events} = message, event),
    do: %{message | events: [event | events]}

  @doc """
  Extracts the aggregate id from `message.raw_request` under `id_field` and copies it
  into `message.aggregate_meta.id`.

  Options:

    * `:generate_if_missing` - when `true` and the id is absent, a fresh UUID is
      generated and written into both `raw_request` and `aggregate_meta`.

  When the id is missing and `:generate_if_missing` is `false` (the default), the
  message is halted with a `Response.missing_id/1` response. This is what the
  `X3m.System.MessageHandler` `on_new_aggregate` / `on_aggregate` macros call for you.

  ## Examples

  When the id is present under `id_field` it is copied into `aggregate_meta`:

      iex> msg = X3m.System.Message.new(:open_account, raw_request: %{"id" => "acc-1"})
      iex> X3m.System.Message.prepare_aggregate_id(msg, "id").aggregate_meta.id
      "acc-1"

  When it is missing and `:generate_if_missing` is not set, the message is halted:

      iex> msg = X3m.System.Message.new(:open_account, raw_request: %{})
      iex> msg = X3m.System.Message.prepare_aggregate_id(msg, "id")
      iex> {msg.halted?, msg.response}
      {true, {:missing_id, "id"}}

  With `generate_if_missing: true` a fresh id is written into both `raw_request` and
  `aggregate_meta`:

      iex> msg = X3m.System.Message.new(:open_account, raw_request: %{})
      iex> msg = X3m.System.Message.prepare_aggregate_id(msg, "id", generate_if_missing: true)
      iex> is_binary(msg.aggregate_meta.id) and msg.raw_request["id"] == msg.aggregate_meta.id
      true
  """
  @spec prepare_aggregate_id(t(), id_field :: term(), opts :: Keyword.t()) :: t()
  def prepare_aggregate_id(%__MODULE__{} = message, id_field, opts \\ []) do
    id =
      message
      |> Map.from_struct()
      |> get_in([:raw_request, id_field])

    case {id, opts[:generate_if_missing] == true} do
      {nil, true} ->
        id = UUID.uuid4()
        raw_request = Map.put(message.raw_request, id_field, id)
        aggregate_meta = Map.put(message.aggregate_meta, :id, id)

        message
        |> Map.put(:raw_request, raw_request)
        |> Map.put(:aggregate_meta, aggregate_meta)

      {nil, false} ->
        response = Response.missing_id(id_field)
        return(message, response)

      _ ->
        aggregate_meta = Map.put(message.aggregate_meta, :id, id)
        Map.put(message, :aggregate_meta, aggregate_meta)
    end
  end

  @doc """
  Generates a new, URL-safe, unique message id.

  This is the same id format used by `new/2` when no `:id` is given.
  """
  # taken from https://github.com/elixir-plug/plug/blob/master/lib/plug/request_id.ex
  @spec gen_msg_id :: String.t()
  def gen_msg_id() do
    binary = <<
      System.system_time(:nanosecond)::64,
      :erlang.phash2({node(), self()}, 16_777_216)::24,
      :erlang.unique_integer()::32
    >>

    Base.url_encode64(binary)
  end
end
