defmodule FuseWeb.CoreComponentsTest do
  use ExUnit.Case, async: true

  import Phoenix.Component, only: [sigil_H: 2]
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

    test "renders a label slot and drives title + aria-label from title" do
      assigns = %{}

      html =
        rendered_to_string(~H"""
        <.copy_button id="c" value="env_x" title="Copy ID">Copy URL</.copy_button>
        """)

      assert html =~ "Copy URL"
      assert html =~ ~s(title="Copy ID")
      assert html =~ ~s(aria-label="Copy ID")
    end
  end
end
