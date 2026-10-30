defmodule BbhWeb.RichtextImagesTest do
  use Bbh.DataCase, async: true

  import Bbh.ContentFixtures
  import BbhWeb.MediaUrlHelpers
  import Phoenix.HTML, only: [safe_to_string: 1]

  alias BbhWeb.RichtextImages

  defp image(attrs \\ %{}) do
    upload_fixture(
      Enum.into(attrs, %{
        content_type: "image/jpeg",
        width: 1000,
        height: 750,
        caption: "Königsschießen 2026",
        copyright: "Max Muster"
      })
    )
  end

  defp img(upload, extra \\ ""), do: ~s(<img src="/media/#{upload.storage_key}"#{extra} />)

  describe "rewrite/1" do
    test "wraps a known image in a figure with variants, dimensions, lightbox and caption" do
      u = image(description: "Der neue König")
      out = unsigned(RichtextImages.rewrite("<p>Text " <> img(u, ~s( alt="alt")) <> " mehr</p>"))
      key = u.storage_key

      assert out =~ ~r{\A<p>Text <span class="bbh-fig">}
      assert out =~ ~s(<button type="button" class="bbh-fig-zoom" aria-label="Bild vergrößern")
      assert out =~ ~s(data-lightbox-src="/media/#{key}?w=1000")
      assert out =~ ~s(data-lightbox-alt="Der neue König")
      assert out =~ ~s(data-lightbox-caption="Königsschießen 2026")
      assert out =~ ~s(data-lightbox-copyright="© Max Muster")
      assert out =~ ~s(data-lightbox-group="content")
      assert out =~ ~s(src="/media/#{key}?w=800")

      # Capped at the original width: no 1200/1600 step, but the exact 1000 one.
      assert out =~
               ~s(srcset="/media/#{key}?w=480 480w, /media/#{key}?w=800 800w, /media/#{key}?w=1000 1000w")

      assert out =~ ~s(width="1000" height="750")
      assert out =~ ~s(alt="Der neue König")
      assert out =~ ~s(loading="lazy")

      assert out =~
               ~s(<span class="bbh-fig-caption"><span class="bbh-fig-text">Königsschießen 2026</span><span class="bbh-fig-copyright">© Max Muster</span></span></span> mehr</p>)
    end

    test "a large original offers every step and opens at 1600 in the lightbox" do
      u = image(width: 4000, height: 3000)
      out = unsigned(RichtextImages.rewrite(img(u)))

      assert out =~ "1600w\""
      refute out =~ "4000w"
      assert out =~ ~s(data-lightbox-src="/media/#{u.storage_key}?w=1600")
    end

    test "a stale ?v= on the stored src resolves; output carries the current revision" do
      u = image(width: 600) |> Ecto.Changeset.change(revision: 3) |> Bbh.Repo.update!()
      out = unsigned(RichtextImages.rewrite(~s(<img src="/media/#{u.storage_key}?v=1" />)))

      assert out =~ ~s(src="/media/#{u.storage_key}?w=600&amp;v=3")
      assert out =~ ~s(srcset="/media/#{u.storage_key}?w=480&amp;v=3 480w)
      refute out =~ "v=1"
    end

    test "unknown keys, non-images and external URLs stay untouched" do
      pdf = upload_fixture(content_type: "application/pdf", storage_key: "docs/a.pdf")

      html =
        ~s(<p><img src="/media/nope/x.jpg" /><img src="/media/#{pdf.storage_key}" />) <>
          ~s(<img src="https://example.com/a.jpg" /></p>)

      assert RichtextImages.rewrite(html) == html
    end

    test "size and float classes move onto the wrapper" do
      u = image()
      out = RichtextImages.rewrite(img(u, ~s( class="bbh-img-sm bbh-float-right")))

      assert out =~ ~s(<span class="bbh-fig bbh-img-sm bbh-float-right">)
      refute out =~ ~r/<img[^>]*class=/
      assert out =~ ~s{sizes="(min-width: 48rem) min(25vw, 13.5rem), 100vw"}
    end

    test "a float without a size gets the half-width sizes" do
      out = RichtextImages.rewrite(img(image(), ~s( class="bbh-float-left")))
      assert out =~ ~s{sizes="(min-width: 48rem) min(50vw, 27rem), 100vw"}
    end

    test "no caption span when the media item has neither caption nor copyright" do
      # The fixture's create changeset defaults the copyright to the club; clear it.
      u = image(caption: nil) |> Ecto.Changeset.change(copyright: nil) |> Bbh.Repo.update!()
      out = RichtextImages.rewrite(img(u))

      refute out =~ "bbh-fig-caption"
      refute out =~ "data-lightbox-caption"
    end

    test "bbh-cap-* picks what the caption line shows; the lightbox keeps both" do
      u = image()
      line = fn class -> RichtextImages.rewrite(img(u, ~s( class="#{class}"))) end

      both = line.("bbh-img-md")
      assert both =~ ~s(<span class="bbh-fig-text">Königsschießen 2026</span>)
      assert both =~ ~s(<span class="bbh-fig-copyright">© Max Muster</span>)

      caption = line.("bbh-cap-caption")
      assert caption =~ "bbh-fig-text"
      refute caption =~ "bbh-fig-copyright"

      copyright = line.("bbh-cap-copyright")
      refute copyright =~ "bbh-fig-text"
      assert copyright =~ "bbh-fig-copyright"

      none = line.("bbh-cap-none")
      refute none =~ "bbh-fig-caption"

      for out <- [caption, copyright, none] do
        assert out =~ ~s(data-lightbox-caption="Königsschießen 2026")
        assert out =~ ~s(data-lightbox-copyright="© Max Muster")
      end
    end

    test "a caption without a copyright renders just the caption" do
      u = image() |> Ecto.Changeset.change(copyright: nil) |> Bbh.Repo.update!()
      out = RichtextImages.rewrite(img(u))

      assert out =~ ~s(<span class="bbh-fig-text">Königsschießen 2026</span></span>)
      refute out =~ "bbh-fig-copyright"
    end

    test "only the caption requested but none set: no caption line" do
      out = RichtextImages.rewrite(img(image(caption: nil), ~s( class="bbh-cap-caption")))
      refute out =~ "bbh-fig-caption"
    end

    test "an image inside a link keeps the link and gets no lightbox button" do
      u = image()

      out =
        RichtextImages.rewrite(~s(<p><a href="/verein">) <> img(u) <> "</a> " <> img(u) <> "</p>")

      [linked, plain] = String.split(out, "</a>")
      refute linked =~ "<button"
      assert linked =~ "srcset="
      assert linked =~ "bbh-fig-caption"
      assert plain =~ "<button"
    end

    test "caption, alt and copyright are HTML-escaped" do
      u = image(caption: ~s(Der "König" <b>), description: ~s(a"b<c), copyright: "A & B")
      out = RichtextImages.rewrite(img(u))

      assert out =~ ~s(alt="a&quot;b&lt;c")
      assert out =~ ~s(data-lightbox-caption="Der &quot;König&quot; &lt;b&gt;")
      assert out =~ ~s(<span class="bbh-fig-text">Der &quot;König&quot; &lt;b&gt;</span>)
      assert out =~ "© A &amp; B"
      refute out =~ "<b>"
    end

    test "GIFs are served as the original, without variants" do
      u = image(content_type: "image/gif")
      out = RichtextImages.rewrite(img(u))

      assert out =~ ~s(src="/media/#{u.storage_key}")
      refute out =~ "srcset"
      assert out =~ ~s(data-lightbox-src="/media/#{u.storage_key}")
    end

    test "several images resolve from one lookup, each with its own upload" do
      a = image(caption: "Erstes")
      b = image(caption: "Zweites")
      out = RichtextImages.rewrite("<p>" <> img(a) <> "</p><p>" <> img(b) <> img(a) <> "</p>")

      captions = Regex.scan(~r/data-lightbox-caption="([^"]*)"/, out, capture: :all_but_first)
      assert captions == [["Erstes"], ["Zweites"], ["Erstes"]]
    end

    test "passes non-binaries through" do
      assert RichtextImages.rewrite(nil) == nil
    end
  end

  describe "BbhWeb.Format.render_richtext/1" do
    test "enriches media images in the rendered body" do
      u = image()
      out = ("<p>" <> img(u) <> "</p>") |> BbhWeb.Format.render_richtext() |> safe_to_string()

      assert out =~ ~s(class="bbh-fig")
      assert out =~ ~s(data-lightbox-group="content")
    end

    test "an address in a caption is obfuscated" do
      u = image(caption: "Fragen an info@example.com")
      out = ("<p>" <> img(u) <> "</p>") |> BbhWeb.Format.render_richtext() |> safe_to_string()

      refute out =~ ~r{<span class="bbh-fig-text">[^<]*info@example\.com}
      assert out =~ ~s(class="eml")
    end
  end
end
