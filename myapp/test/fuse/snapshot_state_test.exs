defmodule Fuse.SnapshotStateTest do
  use ExUnit.Case, async: true
  doctest Fuse.SnapshotState

  alias Fuse.SnapshotState

  test "states/0 and export_states/0" do
    assert SnapshotState.states() == ~w(creating ready restoring deleting error)
    assert SnapshotState.export_states() == ~w(pending ready error)
  end

  describe "cast/1" do
    test "accepts known strings and atoms" do
      assert SnapshotState.cast("ready") == {:ok, "ready"}
      assert SnapshotState.cast(:restoring) == {:ok, "restoring"}
    end

    test "rejects unknown or non-state values" do
      assert SnapshotState.cast("nope") == :error
      assert SnapshotState.cast(nil) == :error
      assert SnapshotState.cast(42) == :error
    end
  end

  test "valid?/1" do
    assert SnapshotState.valid?("creating")
    refute SnapshotState.valid?("pending")
  end

  test "ready?/1" do
    assert SnapshotState.ready?("ready")
    assert SnapshotState.ready?(:ready)
    refute SnapshotState.ready?("creating")
    refute SnapshotState.ready?("bogus")
  end

  test "error?/1" do
    assert SnapshotState.error?("error")
    refute SnapshotState.error?("ready")
  end

  test "in_progress?/1" do
    assert SnapshotState.in_progress?("creating")
    assert SnapshotState.in_progress?("restoring")
    assert SnapshotState.in_progress?("deleting")
    refute SnapshotState.in_progress?("ready")
    refute SnapshotState.in_progress?("error")
    refute SnapshotState.in_progress?("bogus")
  end

  describe "export status helpers" do
    test "export_valid?/1" do
      assert SnapshotState.export_valid?("pending")
      assert SnapshotState.export_valid?(:ready)
      refute SnapshotState.export_valid?("creating")
      refute SnapshotState.export_valid?(nil)
    end

    test "export_ready?/1" do
      assert SnapshotState.export_ready?("ready")
      assert SnapshotState.export_ready?(:ready)
      refute SnapshotState.export_ready?("pending")
      refute SnapshotState.export_ready?(nil)
    end
  end
end
