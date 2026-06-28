defmodule Fuse.ErrorTest do
  use ExUnit.Case, async: true
  doctest Fuse.Error

  alias Fuse.Error

  test "parses the full envelope with string keys" do
    body = %{
      "error" => %{"code" => "not_found", "message" => "no env", "details" => %{"id" => "e1"}}
    }

    assert %Error{code: "not_found", message: "no env", details: %{"id" => "e1"}, status: 404} =
             Error.parse(body, 404)
  end

  test "parses atom-keyed maps" do
    assert %Error{code: "bad", message: "nope"} =
             Error.parse(%{error: %{code: "bad", message: "nope"}})
  end

  test "parses a bare (non-enveloped) error map" do
    assert %Error{code: "conflict", message: "exists"} =
             Error.parse(%{"code" => "conflict", "message" => "exists"})
  end

  test "supplies a fallback message when missing" do
    assert %Error{message: "Unknown fuse error"} = Error.parse(%{"code" => "x"})
  end

  test "defaults status to nil when not provided" do
    assert %Error{status: nil} = Error.parse(%{"error" => %{"message" => "x"}})
  end

  test "handles malformed (non-map) bodies" do
    assert %Error{code: nil, message: "Malformed or unexpected fuse error response", status: 502} =
             Error.parse("<html>502</html>", 502)
  end

  test "builds transport errors" do
    assert %Error{code: "transport_error", details: %{reason: :timeout}, status: nil} =
             Error.transport(:timeout)
  end
end
