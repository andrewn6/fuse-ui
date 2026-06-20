defmodule Fuse.BoundsTest do
  # async: false — the "configurable caps" cases mutate global app config.
  use ExUnit.Case, async: false

  alias Fuse.Bounds
  alias Fuse.Error
  alias Fuse.ResourceSpec

  describe "check/1 against the default caps" do
    test "allows a normal spec" do
      spec =
        ResourceSpec.new!(%{cpus: 4, ram_mb: 8192, storage_gb: 40, max_runtime_seconds: 3600})

      assert Bounds.check(spec) == :ok
    end

    test "rejects a spec that exceeds a cap, naming the field" do
      spec = ResourceSpec.new!(%{cpus: 100_000, ram_mb: 2048, storage_gb: 20})
      assert {:error, %Error{code: "invalid_argument", details: details}} = Bounds.check(spec)
      assert Map.has_key?(details, "cpus")
      refute Map.has_key?(details, "ram_mb")
    end

    test "reports every field that exceeds its cap at once" do
      spec =
        ResourceSpec.new!(%{
          cpus: 100_000,
          ram_mb: 100_000_000,
          storage_gb: 100_000_000,
          max_runtime_seconds: 100_000_000
        })

      assert {:error, %Error{details: details}} = Bounds.check(spec)

      assert details |> Map.keys() |> Enum.sort() ==
               ["cpus", "max_runtime_seconds", "ram_mb", "storage_gb"]
    end

    test "an absent optional field (max_runtime_seconds) is never a violation" do
      spec = ResourceSpec.new!(%{cpus: 1, ram_mb: 512, storage_gb: 10})
      assert Bounds.check(spec) == :ok
    end
  end

  describe "check/1 with configured caps" do
    setup do
      original = Application.get_env(:fuse, Bounds)

      Application.put_env(:fuse, Bounds,
        max_cpus: 2,
        max_ram_mb: 2048,
        max_storage_gb: 20,
        max_runtime_seconds: 3600
      )

      on_exit(fn -> Application.put_env(:fuse, Bounds, original) end)
    end

    test "a spec exactly at the cap is allowed (boundary is inclusive)" do
      spec =
        ResourceSpec.new!(%{cpus: 2, ram_mb: 2048, storage_gb: 20, max_runtime_seconds: 3600})

      assert Bounds.check(spec) == :ok
    end

    test "one over the cap is rejected" do
      spec = ResourceSpec.new!(%{cpus: 3, ram_mb: 2048, storage_gb: 20})
      assert {:error, %Error{details: %{"cpus" => _}}} = Bounds.check(spec)
    end

    test "a nil cap means unlimited for that field" do
      Application.put_env(:fuse, Bounds, max_cpus: nil)
      spec = ResourceSpec.new!(%{cpus: 9_999, ram_mb: 1, storage_gb: 1})
      assert Bounds.check(spec) == :ok
    end
  end
end
