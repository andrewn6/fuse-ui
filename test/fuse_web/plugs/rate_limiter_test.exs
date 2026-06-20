defmodule FuseWeb.Plugs.RateLimiterTest do
  # async: false — mutates global rate-limit config and shares one ETS table.
  use ExUnit.Case, async: false

  import Plug.Test
  import Plug.Conn

  alias FuseWeb.Plugs.RateLimiter

  setup do
    original = Application.get_env(:fuse, RateLimiter)
    on_exit(fn -> Application.put_env(:fuse, RateLimiter, original) end)
    FuseWeb.RateLimiter.reset()
    :ok
  end

  defp build(method, ip \\ {127, 0, 0, 1}) do
    %{conn(method, "/api/v1/environments") | remote_ip: ip}
    |> RateLimiter.call([])
  end

  defp limit(opts), do: Application.put_env(:fuse, RateLimiter, opts)

  test "passes through when no limit is configured" do
    limit(limit: nil, window_ms: 60_000)
    for _ <- 1..50, do: refute(build(:post).halted)
  end

  test "allows up to the limit, then returns 429" do
    limit(limit: 2, window_ms: 60_000)

    refute build(:post).halted
    refute build(:post).halted

    denied = build(:post)
    assert denied.halted
    assert denied.status == 429
    assert get_resp_header(denied, "retry-after") == ["60"]
    assert denied.resp_body =~ "rate_limited"
  end

  test "reads (GET) are never counted or limited" do
    limit(limit: 1, window_ms: 60_000)
    for _ <- 1..10, do: refute(build(:get).halted)
  end

  test "different source IPs get independent buckets" do
    limit(limit: 1, window_ms: 60_000)

    refute build(:post, {10, 0, 0, 1}).halted
    refute build(:post, {10, 0, 0, 2}).halted

    assert build(:post, {10, 0, 0, 1}).halted
  end
end
