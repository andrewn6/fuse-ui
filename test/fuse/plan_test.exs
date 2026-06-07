defmodule Fuse.PlanTest do
  use ExUnit.Case, async: true
  doctest Fuse.Plan

  alias Fuse.Plan
  alias Fuse.ResourceSpec

  test "names/0 lists presets smallest to largest" do
    assert Plan.names() == ~w(tiny small medium large)
  end

  describe "preset/1" do
    test "returns raw attrs for known names (string or atom)" do
      assert Plan.preset("small") == %{cpus: 1, ram_mb: 1024, storage_gb: 20}
      assert Plan.preset(:medium) == %{cpus: 2, ram_mb: 2048, storage_gb: 40}
    end

    test "returns nil for unknown names" do
      assert Plan.preset("nope") == nil
      assert Plan.preset(123) == nil
    end
  end

  describe "spec/2" do
    test "builds a valid ResourceSpec for every preset" do
      for name <- Plan.names() do
        assert {:ok, %ResourceSpec{} = spec} = Plan.spec(name)
        assert spec.cpus > 0
        assert spec.ram_mb > 0
        assert spec.storage_gb > 0
        assert spec.region == nil
        assert spec.max_runtime_seconds == nil
      end
    end

    test "accepts atom names" do
      assert {:ok, %ResourceSpec{cpus: 2, ram_mb: 2048}} = Plan.spec(:medium)
    end

    test "merges region and max_runtime_seconds overrides" do
      assert {:ok, spec} = Plan.spec("tiny", %{region: "us-east", max_runtime_seconds: 3600})
      assert spec.region == "us-east"
      assert spec.max_runtime_seconds == 3600
      # preset sizing is preserved
      assert spec.cpus == 1
    end

    test "accepts string-keyed overrides" do
      assert {:ok, spec} = Plan.spec("tiny", %{"region" => "eu-west"})
      assert spec.region == "eu-west"
    end

    test "returns {:error, :unknown_plan} for unknown names" do
      assert Plan.spec("huge") == {:error, :unknown_plan}
    end

    test "surfaces ResourceSpec validation errors for bad overrides" do
      assert {:error, [region: _]} = Plan.spec("tiny", %{region: 123})
      assert {:error, [max_runtime_seconds: _]} = Plan.spec("tiny", %{max_runtime_seconds: -5})
    end
  end

  describe "spec!/2" do
    test "returns the struct on success" do
      assert %ResourceSpec{cpus: 4} = Plan.spec!("large")
    end

    test "raises on unknown plan" do
      assert_raise ArgumentError, ~r/unknown plan/, fn -> Plan.spec!("huge") end
    end

    test "raises on invalid overrides" do
      assert_raise ArgumentError, ~r/invalid plan overrides/, fn ->
        Plan.spec!("tiny", %{region: 123})
      end
    end
  end
end
