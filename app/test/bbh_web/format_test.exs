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

    test "an untouched image carries no revision — existing URLs stay byte-identical" do
      assert Format.media_url(upload(%{revision: 0}), width: 640) == "/media/2026/x.jpg?w=640"
    end

    test "a rotated image busts the browser cache with v=" do
      assert Format.media_url(upload(%{revision: 2}), width: 640) =~ "v=2"
      assert Format.media_url(upload(%{revision: 1})) == "/media/2026/x.jpg?v=1"
    end
  end

  describe "image metadata" do
    alias Bbh.Content.ArticleImage

    test "alt text prefers the description, then caption, then title" do
      assert Format.image_alt(%Upload{description: "Alt", caption: "Cap", title: "Titel"}) ==
               "Alt"

      assert Format.image_alt(%Upload{caption: "Cap", title: "Titel"}) == "Cap"
      assert Format.image_alt(%Upload{title: "Titel"}) == "Titel"
      assert Format.image_alt(%Upload{}) == "Bild"
      assert Format.image_alt(%Upload{description: "   "}) == "Bild"
      assert Format.image_alt(nil) == "Bild"
    end

    test "an embedding resolves through its media item" do
      image = %ArticleImage{media: %Upload{caption: "Der Thron", copyright: "BBH e.V."}}

      assert Format.image_alt(image) == "Der Thron"
      assert Format.image_caption(image) == "Der Thron"
      assert Format.image_copyright(image) == "BBH e.V."
    end

    test "an article image can suppress the caption without hiding the copyright" do
      image = %ArticleImage{
        show_caption: false,
        media: %Upload{caption: "Der Thron", copyright: "BBH e.V."}
      }

      assert is_nil(Format.image_caption(image))
      assert Format.image_copyright(image) == "BBH e.V."
    end

    test "the copyright gets a © unless it already labels itself" do
      assert Format.copyright_label("Buterland-Beckerhook e.V.") == "© Buterland-Beckerhook e.V."
      assert Format.copyright_label("Max Mustermann") == "© Max Mustermann"

      # A rights holder whose name merely *starts* with one of the label words keeps its ©.
      assert Format.copyright_label("Bildarchiv Stadt Münster") == "© Bildarchiv Stadt Münster"
      assert Format.copyright_label("Fotoclub Nord") == "© Fotoclub Nord"
      assert Format.copyright_label("Quellenhof Fotografie") == "© Quellenhof Fotografie"

      # Already labelled — left exactly as the editor typed it.
      for text <- ["© BBH", "(c) BBH", "Copyright BBH", "Foto: Max", "Bild : Max", "Quelle: WN"] do
        assert Format.copyright_label(text) == text
      end

      assert is_nil(Format.copyright_label(nil))
      assert is_nil(Format.copyright_label("   "))
    end

    test "blank metadata counts as none" do
      image = %ArticleImage{media: %Upload{caption: "  ", copyright: ""}}
      assert is_nil(Format.image_caption(image))
      assert is_nil(Format.image_copyright(image))
      assert is_nil(Format.image_caption(%ArticleImage{}))
    end
  end

  describe "article_hero/1 and throne_picture/1" do
    alias Bbh.Content.{Article, Throne}

    test "article_hero/1 is the article's single image, or nil" do
      img = %Upload{storage_key: "2026/hero.jpg"}
      assert Format.article_hero(%Article{image: img}) == img
      assert is_nil(Format.article_hero(%Article{image: nil}))
    end

    test "throne_picture/1 prefers the throne's own image" do
      own = %Upload{storage_key: "2026/throne.jpg"}
      article_img = %Upload{storage_key: "2026/article.jpg"}
      throne = %Throne{image: own, article: %Article{image: article_img}}
      assert Format.throne_picture(throne) == own
    end

    test "throne_picture/1 falls back to the article image when the throne has none" do
      article_img = %Upload{storage_key: "2026/article.jpg"}
      throne = %Throne{image: nil, article: %Article{image: article_img}}
      assert Format.throne_picture(throne) == article_img
    end

    test "throne_picture/1 is nil when neither the throne nor its article has an image" do
      throne = %Throne{image: nil, article: %Article{image: nil}}
      assert is_nil(Format.throne_picture(throne))
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

    test "tel links are left untouched" do
      refute render(~s(<a href="tel:+491234">Tel</a>)) =~ "target"
    end

    test "a mailto link is obfuscated and never retargeted" do
      html = render(~s(<a href="mailto:info@example.com">Mail</a>))

      refute html =~ "target"
      refute html =~ "mailto"
      refute html =~ "info@example.com"
      assert html =~ "data-eml"
    end

    test "an address typed into the copy is obfuscated" do
      html = render(~s(<p>Schreib an info@example.com.</p>))

      refute html =~ "info@example.com"
      assert html =~ ~s(class="eml")
    end

    test "resolves placeholders alongside link retargeting" do
      html = render(~s(See <a href="https://example.com">site</a>))
      assert html =~ ~s(target="_blank")
    end
  end
end
