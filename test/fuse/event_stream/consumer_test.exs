defmodule Fuse.EventStream.ConsumerTest do
  use ExUnit.Case, async: true

  alias Fuse.Error
  alias Fuse.EventStream.Consumer
  alias Fuse.EventStream.Event
  alias Fuse.EventStream.Source.Fake

  @pubsub Fuse.PubSub

  setup do
    # Unique vm_id per test keeps PubSub topics isolated (async-safe).
    vm_id = "vm-#{System.unique_integer([:positive])}"
    Phoenix.PubSub.subscribe(@pubsub, "environment:#{vm_id}")
    {:ok, vm_id: vm_id}
  end

  defp start_consumer(vm_id, opts \\ []) do
    base = [vm_id: vm_id, source: Fake, backoff_initial: 5, backoff_max: 20]
    start_supervised!({Consumer, Keyword.merge(base, opts)})
  end

  # Build a raw SSE frame the fake will deliver as body bytes.
  defp frame(map), do: "id: #{map["id"] || "x"}\ndata: #{Jason.encode!(map)}\n\n"

  defp feed(pid, vm_id, chunk), do: send(pid, {:fake_sse, vm_id, chunk})

  test "decodes a frame and broadcasts an event", %{vm_id: vm_id} do
    pid = start_consumer(vm_id)
    feed(pid, vm_id, {:data, frame(%{"id" => "e1", "event" => "state", "state" => "running"})})

    assert_receive {:environment_event, %Event{id: "e1", state: "running"}}
  end

  test "reassembles an event split across two data chunks", %{vm_id: vm_id} do
    pid = start_consumer(vm_id)
    raw = frame(%{"id" => "e1", "state" => "running"})
    {head, tail} = String.split_at(raw, 12)

    feed(pid, vm_id, {:data, head})
    refute_receive {:environment_event, _}, 30
    feed(pid, vm_id, {:data, tail})

    assert_receive {:environment_event, %Event{state: "running"}}
  end

  test "ignores keepalive comment frames", %{vm_id: vm_id} do
    pid = start_consumer(vm_id)
    feed(pid, vm_id, {:data, ": keepalive\n\n"})
    refute_receive {:environment_event, _}, 30
  end

  test "stops on a terminal event and does not reopen (terminal is final)", %{vm_id: vm_id} do
    pid = start_consumer(vm_id, source_opts: [notify: self()])
    assert_receive {:fake_open, ^vm_id}
    ref = Process.monitor(pid)

    feed(pid, vm_id, {:data, frame(%{"id" => "e9", "state" => "destroyed"})})

    assert_receive {:environment_event, %Event{state: "destroyed"}}
    assert_receive {:DOWN, ^ref, :process, ^pid, :normal}
    # A completed stream must not be reconnected (would 404-loop in production).
    refute_receive {:fake_open, ^vm_id}
  end

  test "drops an undecodable frame without crashing", %{vm_id: vm_id} do
    pid = start_consumer(vm_id)
    ref = Process.monitor(pid)

    feed(pid, vm_id, {:data, "data: {not json\n\n"})
    feed(pid, vm_id, {:data, frame(%{"id" => "e2", "state" => "running"})})

    assert_receive {:environment_event, %Event{id: "e2"}}
    refute_received {:DOWN, ^ref, :process, ^pid, _}
  end

  test "reconnects on a stream error", %{vm_id: vm_id} do
    # notify makes each open observable; expect a second open after the error.
    pid = start_consumer(vm_id, source_opts: [notify: self()])

    assert_receive {:fake_open, ^vm_id}
    feed(pid, vm_id, {:error, :closed})
    assert_receive {:fake_open, ^vm_id}, 200
    assert Process.alive?(pid)
  end

  test "reconnects on unexpected EOF (:done without a terminal event)", %{vm_id: vm_id} do
    pid = start_consumer(vm_id, source_opts: [notify: self()])

    assert_receive {:fake_open, ^vm_id}
    feed(pid, vm_id, :done)
    assert_receive {:fake_open, ^vm_id}, 200
    assert Process.alive?(pid)
  end

  test "stops when its last monitored subscriber exits", %{vm_id: vm_id} do
    sub = spawn(fn -> Process.sleep(:infinity) end)
    pid = start_consumer(vm_id, subscriber: sub)
    ref = Process.monitor(pid)

    Process.exit(sub, :kill)

    assert_receive {:DOWN, ^ref, :process, ^pid, :normal}
  end

  test "keeps running while another subscriber remains", %{vm_id: vm_id} do
    s1 = spawn(fn -> Process.sleep(:infinity) end)
    s2 = spawn(fn -> Process.sleep(:infinity) end)
    pid = start_consumer(vm_id, subscriber: s1)
    :ok = Consumer.add_subscriber(pid, s2)
    ref = Process.monitor(pid)

    Process.exit(s1, :kill)
    refute_receive {:DOWN, ^ref, :process, ^pid, _}, 50
    assert Process.alive?(pid)

    # the last subscriber leaving stops it
    Process.exit(s2, :kill)
    assert_receive {:DOWN, ^ref, :process, ^pid, :normal}
  end

  test "a consumer started without a subscriber is not stopped by subscriber teardown",
       %{vm_id: vm_id} do
    pid = start_consumer(vm_id)
    ref = Process.monitor(pid)

    # an untracked DOWN must be ignored, not interpreted as a teardown
    send(pid, {:DOWN, make_ref(), :process, self(), :normal})

    refute_receive {:DOWN, ^ref, :process, ^pid, _}, 50
    assert Process.alive?(pid)
  end

  test "stops and broadcasts down on a permanent open error (not_found)", %{vm_id: vm_id} do
    error = %Error{code: "not_found", message: "no such env"}

    # Uses the Consumer's real :transient child spec (no restart override), so a
    # :normal stop here genuinely stays stopped.
    start_supervised!(
      {Consumer,
       [vm_id: vm_id, source: Fake, source_opts: [result: {:error, error}, notify: self()]]}
    )

    # The down broadcast is emitted in the same callback that stops the consumer,
    # so receiving it proves the stop-without-reconnect path ran.
    assert_receive {:fake_open, ^vm_id}
    assert_receive {:environment_stream_down, ^vm_id, %Error{code: "not_found"}}
    refute_receive {:fake_open, ^vm_id}
  end
end
