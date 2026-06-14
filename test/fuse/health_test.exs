defmodule Fuse.HealthTest do
  use ExUnit.Case, async: true

  alias Fuse.Error
  alias Fuse.Health

  # config/test.exs already points :fuse_client at the in-memory Fake; each test
  # starts it in this process with the readiness result it wants to simulate.

  test "ok when the readiness probe returns 200" do
    {:ok, _} = Fuse.Client.Fake.start_link()
    assert Health.check() == :ok
  end

  test "degraded when the readiness probe returns 503" do
    error = %Error{code: "unavailable", message: "dependency down", status: 503}
    {:ok, _} = Fuse.Client.Fake.start_link(ready: {:error, error})
    assert Health.check() == :degraded
  end

  test "unreachable on a transport error" do
    error = %Error{code: "transport_error", message: "econnrefused"}
    {:ok, _} = Fuse.Client.Fake.start_link(ready: {:error, error})
    assert Health.check() == :unreachable
  end
end
