defmodule Fuse.ApplicationTest do
  # async: false — toggles the global :env and ApiAuth token config.
  use ExUnit.Case, async: false

  import ExUnit.CaptureLog

  setup do
    prev_env = Application.get_env(:fuse, :env)
    prev_auth = Application.get_env(:fuse, FuseWeb.Plugs.ApiAuth)

    on_exit(fn ->
      Application.put_env(:fuse, :env, prev_env)
      Application.put_env(:fuse, FuseWeb.Plugs.ApiAuth, prev_auth)
    end)

    :ok
  end

  defp set(env, token) do
    Application.put_env(:fuse, :env, env)
    Application.put_env(:fuse, FuseWeb.Plugs.ApiAuth, token: token)
  end

  test "warns in prod when the inbound token is unset" do
    set(:prod, nil)
    log = capture_log(fn -> Fuse.Application.warn_if_insecure_prod() end)
    assert log =~ "CONTROL_PLANE_TOKEN is unset"
    assert log =~ "UNAUTHENTICATED"
  end

  test "warns in prod when the inbound token is empty" do
    set(:prod, "")
    log = capture_log(fn -> Fuse.Application.warn_if_insecure_prod() end)
    assert log =~ "CONTROL_PLANE_TOKEN is unset"
  end

  test "does not warn in prod when a token is set" do
    set(:prod, "a-real-token")
    log = capture_log(fn -> Fuse.Application.warn_if_insecure_prod() end)
    refute log =~ "CONTROL_PLANE_TOKEN"
  end

  test "does not warn outside prod even without a token" do
    set(:dev, nil)
    log = capture_log(fn -> Fuse.Application.warn_if_insecure_prod() end)
    refute log =~ "CONTROL_PLANE_TOKEN"
  end
end
