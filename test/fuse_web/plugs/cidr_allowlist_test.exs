defmodule FuseWeb.Plugs.CidrAllowlistTest do
  # async: false — mutates global allowlist config.
  use ExUnit.Case, async: false

  import Plug.Test

  alias FuseWeb.Plugs.CidrAllowlist

  setup do
    original = Application.get_env(:fuse, CidrAllowlist)
    on_exit(fn -> Application.put_env(:fuse, CidrAllowlist, original) end)
    :ok
  end

  defp build(ip) do
    %{conn(:post, "/api/v1/environments") | remote_ip: ip}
    |> CidrAllowlist.call([])
  end

  defp allow(cidrs), do: Application.put_env(:fuse, CidrAllowlist, cidrs: cidrs)

  test "passes through when the allowlist is empty (open to all)" do
    allow([])
    refute build({203, 0, 113, 5}).halted
  end

  test "allows an IPv4 address inside an allowed range" do
    allow(["10.0.0.0/8"])
    refute build({10, 1, 2, 3}).halted
  end

  test "rejects an IPv4 address outside every allowed range with 403" do
    allow(["10.0.0.0/8", "192.168.1.0/24"])

    denied = build({203, 0, 113, 5})
    assert denied.halted
    assert denied.status == 403
    assert denied.resp_body =~ "forbidden"
  end

  test "respects the prefix boundary of a /24" do
    allow(["192.168.1.0/24"])
    refute build({192, 168, 1, 255}).halted
    assert build({192, 168, 2, 1}).halted
  end

  test "matches an IPv6 address inside an allowed range" do
    allow(["2001:db8::/32"])
    refute build({0x2001, 0x0DB8, 0, 0, 0, 0, 0, 1}).halted
    assert build({0x2001, 0x0DB9, 0, 0, 0, 0, 0, 1}).halted
  end

  test "ignores an unparseable CIDR (only the valid ones gate)" do
    allow(["garbage", "10.0.0.0/8"])
    refute build({10, 9, 9, 9}).halted
    assert build({11, 0, 0, 1}).halted
  end

  test "an allowlist of only-invalid entries is treated as empty (open)" do
    allow(["nonsense/99"])
    refute build({203, 0, 113, 5}).halted
  end
end
