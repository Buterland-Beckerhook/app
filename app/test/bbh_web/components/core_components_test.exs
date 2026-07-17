defmodule BbhWeb.CoreComponentsTest do
  use ExUnit.Case, async: true

  import Phoenix.LiveViewTest
  import BbhWeb.CoreComponents

  describe "flash/1 auto-hide" do
    test "auto-hiding flash carries a duration var and the progress bar" do
      html = render_component(&flash/1, kind: :info, flash: %{"info" => "Gespeichert"})

      assert html =~ "Gespeichert"
      assert html =~ "--flash-duration:"
      assert html =~ "flash-progress"
    end

    test "info and error use different default durations" do
      info = render_component(&flash/1, kind: :info, flash: %{"info" => "x"})
      error = render_component(&flash/1, kind: :error, flash: %{"error" => "x"})

      assert info =~ "--flash-duration: 5000ms"
      assert error =~ "--flash-duration: 8000ms"
    end

    test "a custom duration overrides the per-kind default" do
      html = render_component(&flash/1, kind: :info, duration: 3000, flash: %{"info" => "x"})
      assert html =~ "--flash-duration: 3000ms"
    end

    test "autohide=false renders no duration or progress bar" do
      html =
        render_component(&flash/1,
          kind: :error,
          autohide: false,
          flash: %{"error" => "Verbindung verloren"}
        )

      assert html =~ "Verbindung verloren"
      refute html =~ "--flash-duration:"
      refute html =~ "flash-progress"
    end
  end
end
