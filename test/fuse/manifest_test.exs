defmodule Fuse.ManifestTest do
  use ExUnit.Case, async: true
  doctest Fuse.Manifest

  alias Fuse.Manifest

  test "round-trips a nested manifest map" do
    manifest = %{"version" => "1", "services" => %{"web" => %{"image" => "nginx"}}}
    assert {:ok, encoded} = Manifest.encode(manifest)
    assert is_binary(encoded)
    assert {:ok, ^manifest} = Manifest.decode(encoded)
  end

  test "encoded output is standard base64 of the JSON" do
    assert {:ok, encoded} = Manifest.encode(%{"a" => 1})
    assert {:ok, json} = Base.decode64(encoded)
    assert json == ~s({"a":1})
  end

  test "decode/1 rejects invalid base64" do
    assert Manifest.decode("not base64!!") == {:error, :invalid_base64}
  end

  test "decode/1 rejects valid base64 that isn't JSON" do
    encoded = Base.encode64("this is not json")
    assert Manifest.decode(encoded) == {:error, :invalid_json}
  end

  test "encode!/1 and decode!/1 round-trip" do
    encoded = Manifest.encode!(%{"k" => "v"})
    assert Manifest.decode!(encoded) == %{"k" => "v"}
  end

  test "decode!/1 raises on bad input" do
    assert_raise ArgumentError, ~r/could not decode manifest/, fn ->
      Manifest.decode!("!!!")
    end
  end
end
