defmodule Fuse.StateTest do
  use ExUnit.Case, async: true
  doctest Fuse.State

  alias Fuse.State

  test "states/0 lists every known state" do
    assert State.states() == ~w(provisioning running draining destroying destroyed failed)
  end

  test "terminal_states/0" do
    assert State.terminal_states() == ~w(destroyed failed)
  end

  describe "cast/1" do
    test "accepts known strings and atoms" do
      assert State.cast("running") == {:ok, "running"}
      assert State.cast(:draining) == {:ok, "draining"}
    end

    test "rejects unknown or non-state values" do
      assert State.cast("nope") == :error
      assert State.cast(nil) == :error
      assert State.cast(123) == :error
    end
  end

  test "valid?/1" do
    assert State.valid?("running")
    assert State.valid?(:provisioning)
    refute State.valid?("nope")
  end

  test "running?/1" do
    assert State.running?("running")
    refute State.running?("draining")
    refute State.running?("bogus")
  end

  describe "terminal?/1 and active?/1" do
    test "terminal states" do
      assert State.terminal?("destroyed")
      assert State.terminal?("failed")
      refute State.terminal?("running")
      refute State.terminal?("bogus")
    end

    test "active states are valid and non-terminal" do
      assert State.active?("provisioning")
      assert State.active?("draining")
      refute State.active?("destroyed")
      refute State.active?("bogus")
    end
  end

  describe "transitions/1 and can_transition?/2" do
    test "running can drain, destroy, or fail" do
      assert State.transitions("running") == ~w(draining destroying destroyed failed)
    end

    test "terminal states have no outgoing transitions" do
      assert State.transitions("destroyed") == []
      assert State.transitions("failed") == []
    end

    test "unknown state yields []" do
      assert State.transitions("bogus") == []
    end

    test "can_transition?/2 honours the transition map" do
      assert State.can_transition?("provisioning", "running")
      assert State.can_transition?("running", "draining")
      assert State.can_transition?(:running, :failed)
      refute State.can_transition?("running", "provisioning")
      refute State.can_transition?("destroyed", "running")
      refute State.can_transition?("running", "bogus")
    end
  end
end
