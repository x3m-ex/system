defmodule X3m.System.MessageTest do
  use ExUnit.Case, async: true
  alias X3m.System.{Message, Response}

  doctest X3m.System.Message

  describe "gen_msg_id/0" do
    test "produces distinct ids" do
      ids = for _ <- 1..100, do: Message.gen_msg_id()
      assert length(Enum.uniq(ids)) == 100
    end

    test "produces url-safe ids" do
      assert Message.gen_msg_id() =~ ~r/^[A-Za-z0-9_-]+$/
    end
  end

  describe "new/2 defaults" do
    test "reply_to defaults to the calling process" do
      assert Message.new(:svc).reply_to == self()
    end

    test "correlation_id and causation_id fall back to id" do
      msg = Message.new(:svc, id: "m-1")
      assert msg.correlation_id == "m-1"
      assert msg.causation_id == "m-1"
    end

    test "dry_run is false, valid? true, halted? false by default" do
      msg = Message.new(:svc)
      assert msg.dry_run == false
      assert msg.valid? == true
      assert msg.halted? == false
    end

    test "captures current Logger.metadata" do
      Logger.metadata(trace_id: "t-1")
      assert Message.new(:svc).logger_metadata[:trace_id] == "t-1"
    end
  end

  describe "new_caused_by/3" do
    test "preserves correlation_id and sets causation_id to the parent id" do
      # distinct id and correlation_id so the two invariants can't be conflated:
      # correlation_id threads through the whole conversation, causation_id points
      # at the direct parent.
      parent = Message.new(:open_account, id: "p-1", correlation_id: "c-1")
      child = Message.new_caused_by(:notify_owner, parent)
      assert child.correlation_id == "c-1"
      assert child.causation_id == "p-1"
      refute child.id == "p-1"
    end

    test "passes raw_request through" do
      parent = Message.new(:open_account)
      child = Message.new_caused_by(:notify_owner, parent, raw_request: %{"x" => 1})
      assert child.raw_request == %{"x" => 1}
    end
  end

  describe "return/2" do
    test "reverses accumulated events into insertion order and halts" do
      returned =
        :svc
        |> Message.new()
        |> Message.add_event(:first)
        |> Message.add_event(:second)
        |> Message.return(Response.ok())

      assert returned.events == [:first, :second]
      assert returned.halted? == true
      assert returned.response == :ok
    end
  end

  describe "put_request/2" do
    test "stores a valid request and keeps the message open" do
      msg = Message.put_request(%{owner: "Ada"}, Message.new(:open_account))
      assert msg.valid? == true
      assert msg.request == %{owner: "Ada"}
      assert msg.halted? == false
    end

    test "halts with a validation_error when the request is invalid" do
      msg = Message.put_request(%{valid?: false}, Message.new(:open_account))
      assert msg.valid? == false
      assert msg.halted? == true
      assert msg.response == {:validation_error, %{valid?: false}}
    end
  end
end
