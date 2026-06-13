defmodule FuseWeb.CoreComponentsTest do
  use ExUnit.Case, async: true

  import Phoenix.LiveViewTest
  import FuseWeb.CoreComponents

  describe "copy_button/1" do
    test "carries the value, id and clipboard hook" do
      html = render_component(&copy_button/1, id: "copy-x", value: "env_123")

      assert html =~ ~s(id="copy-x")
      assert html =~ ~s(data-copy="env_123")
      assert html =~ "phx-hook"
      assert html =~ "hero-clipboard-document"
      # the confirm icon starts hidden
      assert html =~ "hero-check"
    end

    test "defaults the accessible label to Copy" do
      html = render_component(&copy_button/1, id: "c", value: "v")
      assert html =~ ~s(aria-label="Copy")
    end
  end
end
