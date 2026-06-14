defmodule Fuse.EventStreamTest do
  # async: false — exercises the application-wide Supervisor/Registry singletons.
  use ExUnit.Case, async: false

  alias Fuse.EventStream
  alias Fuse.EventStream.Event

  setup do
    vm_id = "vm-#{System.unique_integer([:positive])}"
    on_exit(fn -> EventStream.unwatch(vm_id) end)
    {:ok, vm_id: vm_id}
  end

  test "watch starts a consumer and registers it", %{vm_id: vm_id} do
    refute EventStream.watching?(vm_id)
    assert {:ok, pid} = EventStream.watch(vm_id)
    assert EventStream.watching?(vm_id)
    assert EventStream.whereis(vm_id) == pid
  end

  test "watch is idempotent for the same vm_id", %{vm_id: vm_id} do
    assert {:ok, pid} = EventStream.watch(vm_id)
    assert {:ok, ^pid} = EventStream.watch(vm_id)
  end

  test "unwatch terminates the consumer", %{vm_id: vm_id} do
    {:ok, pid} = EventStream.watch(vm_id)
    ref = Process.monitor(pid)

    assert :ok = EventStream.unwatch(vm_id)
    assert_receive {:DOWN, ^ref, :process, ^pid, _}
    refute EventStream.watching?(vm_id)
  end

  test "unwatch on an unwatched vm_id is a no-op", %{vm_id: vm_id} do
    assert :ok = EventStream.unwatch(vm_id)
  end

  test "events broadcast end-to-end to subscribers", %{vm_id: vm_id} do
    EventStream.subscribe(vm_id)
    {:ok, pid} = EventStream.watch(vm_id)

    frame = ~s(data: {"id":"e1","event":"state","state":"running"}\n\n)
    send(pid, {:fake_sse, vm_id, {:data, frame}})

    assert_receive {:environment_event, %Event{id: "e1", state: "running"}}
  end

  test "the consumer is torn down when its last subscriber process dies", %{vm_id: vm_id} do
    parent = self()

    # a stand-in viewer that watches with itself as the monitored subscriber
    sub =
      spawn(fn ->
        {:ok, _} = EventStream.watch(vm_id, subscriber: self())
        send(parent, :watched)
        Process.sleep(:infinity)
      end)

    assert_receive :watched
    assert EventStream.watching?(vm_id)
    pid = EventStream.whereis(vm_id)
    ref = Process.monitor(pid)

    Process.exit(sub, :kill)

    assert_receive {:DOWN, ^ref, :process, ^pid, :normal}
    refute EventStream.watching?(vm_id)
  end
end
