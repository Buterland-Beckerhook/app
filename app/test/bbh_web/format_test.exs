defmodule BbhWeb.FormatTest do
  use ExUnit.Case, async: true

  import Phoenix.HTML, only: [safe_to_string: 1]

  alias Bbh.Media.Upload
  alias BbhWeb.Format

  describe "media_url/2" do
    defp upload(attrs \\ %{}), do: struct(%Upload{storage_key: "2026/x.jpg"}, attrs)

    test "no options serves the original" do
      assert Format.media_url(upload()) == "/media/2026/x.jpg"
    end

    test "width/height become query params" do
      assert Format.media_url(upload(), width: 640, height: 380) ==
               "/media/2026/x.jpg?w=640&h=380"
    end

    test "focal point is appended only on a cover crop (both dimensions)" do
      up = upload(%{focal_point_x: 0.25, focal_point_y: 0.75})
      url = Format.media_url(up, width: 640, height: 380)
      assert url =~ "fx=0.25"
      assert url =~ "fy=0.75"
    end

    test "focal point is omitted without both dimensions" do
      up = upload(%{focal_point_x: 0.25, focal_point_y: 0.75})
      refute Format.media_url(up, width: 640) =~ "fx="
      refute Format.media_url(up) =~ "fx="
    end

    test "no focal point means no fx/fy" do
      refute Format.media_url(upload(), width: 640, height: 380) =~ "fx="
    end
  end

  describe "render_richtext/1" do
    defp render(body), do: body |> BbhWeb.Format.render_richtext() |> safe_to_string()

    test "nil passes through" do
      assert BbhWeb.Format.render_richtext(nil) == nil
    end

    test "internal page link opens in place (no target)" do
      html = render(~s(<a href="/vorstand">Vorstand</a>))
      refute html =~ "target"
    end

    test "fragment link opens in place" do
      html = render(~s(<a href="#kontakt">Kontakt</a>))
      refute html =~ "target"
    end

    test "media link opens in a new tab" do
      html = render(~s(<a href="/media/2026/x.pdf">PDF</a>))
      assert html =~ ~s(target="_blank")
      assert html =~ ~s(rel="noopener noreferrer")
    end

    test "external site opens in a new tab" do
      html = render(~s(<a href="https://example.com/page">Extern</a>))
      assert html =~ ~s(target="_blank" rel="noopener noreferrer")
    end

    test "absolute link to our own host opens in place" do
      # Endpoint host is "localhost" in the test/dev config.
      html = render(~s(<a href="https://localhost/impressum">Impressum</a>))
      refute html =~ "target"
    end

    test "absolute link to our own host but /media/ opens in a new tab" do
      html = render(~s(<a href="https://localhost/media/x.pdf">PDF</a>))
      assert html =~ ~s(target="_blank")
    end

    test "mailto/tel links are left untouched" do
      assert render(~s(<a href="mailto:info@example.com">Mail</a>)) |> String.contains?("target") ==
               false

      assert render(~s(<a href="tel:+491234">Tel</a>)) |> String.contains?("target") == false
    end

    test "resolves placeholders alongside link retargeting" do
      html = render(~s(See <a href="https://example.com">site</a>))
      assert html =~ ~s(target="_blank")
    end
  end
end
