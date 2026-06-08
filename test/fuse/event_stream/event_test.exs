defmodule Fuse.EventStream.EventTest do
  use ExUnit.Case, async: true

  alias Fuse.EventStream.Event

  test "from_wire/1 maps the event JSON, including the renamed kind field" do
    event =
      Event.from_wire(%{
        "id" => "ev-1",
        "event" => "state",
        "vm_id" => "vm-1",
        "state" => "running",
        "url" => "https://vm-1.fuse.test",
        "updated_at" => "2026-02-01T00:00:00Z"
      })

    assert %Event{
             id: "ev-1",
             kind: "state",
             vm_id: "vm-1",
             state: "running",
             url: "https://vm-1.fuse.test"
           } = event

    assert %DateTime{} = event.updated_at
    assert event.error == nil
  end

  test "from_wire/1 tolerates missing optional fields" do
    assert %Event{state: "provisioning", url: nil, error: nil, updated_at: nil} =
             Event.from_wire(%{"event" => "state", "vm_id" => "vm-1", "state" => "provisioning"})
  end

  test "terminal?/1 is true for destroyed and failed only" do
    for state <- ~w(destroyed failed) do
      assert Event.terminal?(Event.from_wire(%{"state" => state}))
    end

    for state <- ~w(provisioning running draining destroying) do
      refute Event.terminal?(Event.from_wire(%{"state" => state}))
    end

    refute Event.terminal?(Event.from_wire(%{"state" => nil}))
  end
end
