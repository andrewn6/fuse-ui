defmodule Fuse.ResourceSpecTest do
  use ExUnit.Case, async: true

  alias Fuse.ResourceSpec

  doctest Fuse.ResourceSpec

  describe "new/1 building" do
    test "builds from atom-keyed map" do
      assert {:ok, %ResourceSpec{} = spec} =
               ResourceSpec.new(%{cpus: 2, ram_mb: 2048, storage_gb: 20})

      assert spec.cpus == 2
      assert spec.ram_mb == 2048
      assert spec.storage_gb == 20
      assert spec.region == nil
      assert spec.max_runtime_seconds == nil
    end

    test "builds from string-keyed map" do
      assert {:ok, %ResourceSpec{} = spec} =
               ResourceSpec.new(%{
                 "cpus" => 1,
                 "ram_mb" => 512,
                 "storage_gb" => 10,
                 "region" => "us-east",
                 "max_runtime_seconds" => 3600
               })

      assert spec.cpus == 1
      assert spec.ram_mb == 512
      assert spec.storage_gb == 10
      assert spec.region == "us-east"
      assert spec.max_runtime_seconds == 3600
    end

    test "defaults region and max_runtime_seconds to nil" do
      assert {:ok, %ResourceSpec{region: nil, max_runtime_seconds: nil}} =
               ResourceSpec.new(%{cpus: 1, ram_mb: 256, storage_gb: 5})
    end

    test "accepts optional fields when valid" do
      assert {:ok, %ResourceSpec{region: "eu-west", max_runtime_seconds: 120}} =
               ResourceSpec.new(%{
                 cpus: 4,
                 ram_mb: 8192,
                 storage_gb: 100,
                 region: "eu-west",
                 max_runtime_seconds: 120
               })
    end
  end

  describe "new/1 required-field errors" do
    test "missing cpus" do
      assert {:error, errors} = ResourceSpec.new(%{ram_mb: 512, storage_gb: 10})
      assert errors[:cpus] == "is required"
    end

    test "missing ram_mb" do
      assert {:error, errors} = ResourceSpec.new(%{cpus: 1, storage_gb: 10})
      assert errors[:ram_mb] == "is required"
    end

    test "missing storage_gb" do
      assert {:error, errors} = ResourceSpec.new(%{cpus: 1, ram_mb: 512})
      assert errors[:storage_gb] == "is required"
    end

    test "all required missing returns each error in field order" do
      assert {:error, errors} = ResourceSpec.new(%{})

      assert errors == [
               cpus: "is required",
               ram_mb: "is required",
               storage_gb: "is required"
             ]
    end
  end

  describe "new/1 type errors for required fields" do
    test "non-positive integer is rejected" do
      assert {:error, errors} = ResourceSpec.new(%{cpus: 0, ram_mb: 512, storage_gb: 10})
      assert errors[:cpus] == "must be a positive integer"
    end

    test "negative integer is rejected" do
      assert {:error, errors} = ResourceSpec.new(%{cpus: 1, ram_mb: -5, storage_gb: 10})
      assert errors[:ram_mb] == "must be a positive integer"
    end

    test "non-integer value is rejected" do
      assert {:error, errors} = ResourceSpec.new(%{cpus: 1, ram_mb: 512, storage_gb: "10"})
      assert errors[:storage_gb] == "must be a positive integer"
    end

    test "float value is rejected" do
      assert {:error, errors} = ResourceSpec.new(%{cpus: 1.5, ram_mb: 512, storage_gb: 10})
      assert errors[:cpus] == "must be a positive integer"
    end
  end

  describe "new/1 optional-field type errors" do
    test "region must be a non-empty string" do
      assert {:error, errors} =
               ResourceSpec.new(%{cpus: 1, ram_mb: 512, storage_gb: 10, region: ""})

      assert errors[:region] == "must be a non-empty string"
    end

    test "region wrong type is rejected" do
      assert {:error, errors} =
               ResourceSpec.new(%{cpus: 1, ram_mb: 512, storage_gb: 10, region: 123})

      assert errors[:region] == "must be a non-empty string"
    end

    test "max_runtime_seconds must be a positive integer" do
      assert {:error, errors} =
               ResourceSpec.new(%{
                 cpus: 1,
                 ram_mb: 512,
                 storage_gb: 10,
                 max_runtime_seconds: 0
               })

      assert errors[:max_runtime_seconds] == "must be a positive integer"
    end

    test "max_runtime_seconds wrong type is rejected" do
      assert {:error, errors} =
               ResourceSpec.new(%{
                 cpus: 1,
                 ram_mb: 512,
                 storage_gb: 10,
                 max_runtime_seconds: "soon"
               })

      assert errors[:max_runtime_seconds] == "must be a positive integer"
    end
  end

  describe "new/1 with non-map input" do
    test "returns a base error for a list" do
      assert ResourceSpec.new([]) == {:error, [base: "must be a map of resource attributes"]}
    end

    test "returns a base error for nil" do
      assert ResourceSpec.new(nil) == {:error, [base: "must be a map of resource attributes"]}
    end
  end

  describe "new!/1" do
    test "returns the struct on valid input" do
      assert %ResourceSpec{cpus: 2, ram_mb: 2048, storage_gb: 20} =
               ResourceSpec.new!(%{cpus: 2, ram_mb: 2048, storage_gb: 20})
    end

    test "raises ArgumentError on invalid input" do
      assert_raise ArgumentError, fn ->
        ResourceSpec.new!(%{ram_mb: 512, storage_gb: 10})
      end
    end
  end

  describe "to_wire/1" do
    test "omits nil optional fields" do
      spec = ResourceSpec.new!(%{cpus: 2, ram_mb: 2048, storage_gb: 20})

      assert ResourceSpec.to_wire(spec) == %{
               "cpus" => 2,
               "ram_mb" => 2048,
               "storage_gb" => 20
             }
    end

    test "includes optional fields when present" do
      spec =
        ResourceSpec.new!(%{
          cpus: 4,
          ram_mb: 8192,
          storage_gb: 100,
          region: "us-east",
          max_runtime_seconds: 3600
        })

      assert ResourceSpec.to_wire(spec) == %{
               "cpus" => 4,
               "ram_mb" => 8192,
               "storage_gb" => 100,
               "region" => "us-east",
               "max_runtime_seconds" => 3600
             }
    end

    test "includes only the optional fields that are set" do
      spec = ResourceSpec.new!(%{cpus: 1, ram_mb: 512, storage_gb: 10, region: "eu-west"})

      assert ResourceSpec.to_wire(spec) == %{
               "cpus" => 1,
               "ram_mb" => 512,
               "storage_gb" => 10,
               "region" => "eu-west"
             }
    end
  end
end
