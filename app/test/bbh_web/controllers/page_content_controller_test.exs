defmodule BbhWeb.PageContentControllerTest do
  use BbhWeb.ConnCase, async: true

  import Bbh.ContentFixtures
  import Bbh.ClubFixtures

  test "GET /verein lists published top-level pages", %{conn: conn} do
    page_fixture(slug: "ueber-uns", title: "Über uns", status: "published")
    html = conn |> get(~p"/verein") |> html_response(200)
    assert html =~ "Über uns"
    assert html =~ ~s(href="/verein/ueber-uns")
  end

  test "GET /verein/vorstand lists board members", %{conn: conn} do
    page_fixture(slug: "vorstand", title: "Vorstand", status: "published")
    person = person_fixture(name: "Vorstandsmitglied", role: "vorstand")
    html = conn |> get(~p"/verein/vorstand") |> html_response(200)
    assert html =~ person.name
  end

  test "GET a nested page renders with its breadcrumb chain", %{conn: conn} do
    parent = page_fixture(slug: "ueber-uns", title: "Über uns", status: "published")

    page_fixture(
      slug: "vereinsgeschichte",
      title: "Vereinsgeschichte",
      status: "published",
      parent_id: parent.id
    )

    html = conn |> get(~p"/verein/ueber-uns/vereinsgeschichte") |> html_response(200)
    assert html =~ "Vereinsgeschichte"
    assert html =~ "Über uns"
  end

  test "GET a child via its flat (non-canonical) path 301-redirects to the nested URL", %{
    conn: conn
  } do
    parent = page_fixture(slug: "ueber-uns", status: "published")
    page_fixture(slug: "vereinsgeschichte", status: "published", parent_id: parent.id)

    conn = get(conn, ~p"/verein/vereinsgeschichte")
    assert redirected_to(conn, 301) == "/verein/ueber-uns/vereinsgeschichte"
  end

  test "GET a top-level page renders", %{conn: conn} do
    page_fixture(slug: "mitglied-werden", title: "Mitglied werden", status: "published")
    html = conn |> get(~p"/verein/mitglied-werden") |> html_response(200)
    assert html =~ "Mitglied werden"
  end

  test "a gallery block renders its images in order, with lightbox metadata", %{conn: conn} do
    page = page_fixture(slug: "bilder", title: "Bilder", status: "published")
    {:ok, _} = Bbh.Content.add_block(page, "image_gallery")
    [{_pb, gallery}] = Bbh.Content.load_blocks(Bbh.Content.get_page!(page.id))

    first = upload_fixture(%{caption: "Antreten", copyright: "BBH e.V."})
    second = upload_fixture(%{caption: "Fahnenschwenken"})
    {:ok, _} = Bbh.Content.add_gallery_file(gallery, first.id)
    {:ok, file} = Bbh.Content.add_gallery_file(gallery, second.id)

    html = conn |> get(~p"/verein/bilder") |> html_response(200)

    # Caption and copyright come from the media library and ride along for the
    # enlarged view; the thumbnails themselves stay bare.
    assert html =~ ~s(data-lightbox-caption="Antreten")
    assert html =~ ~s(data-lightbox-copyright="© BBH e.V.")
    # Both must actually be present — see the note in article_controller_test.exs.
    assert {antreten, _} = :binary.match(html, "Antreten")
    assert {schwenken, _} = :binary.match(html, "Fahnenschwenken")
    assert antreten < schwenken

    # Reordering in the admin reorders the public gallery.
    {:ok, _} = Bbh.Content.move_gallery_file(gallery.id, file, :up)
    html = conn |> get(~p"/verein/bilder") |> html_response(200)
    assert {schwenken, _} = :binary.match(html, "Fahnenschwenken")
    assert {antreten, _} = :binary.match(html, "Antreten")
    assert schwenken < antreten
  end

  test "a media_card block wears card chrome only when shadow is enabled", %{conn: conn} do
    page = page_fixture(slug: "karte", title: "Karte", status: "published")
    {:ok, _} = Bbh.Content.add_block(page, "media_card")
    [{pb, _block}] = Bbh.Content.load_blocks(Bbh.Content.get_page!(page.id))

    chrome = "rounded-[18px] border border-base-300 bg-card p-6 shadow-lg sm:p-8"

    # Off (default): plain layout, no card chrome.
    html = conn |> get(~p"/verein/karte") |> html_response(200)
    refute html =~ chrome

    # On: the card gets the shadowed chrome wrapper.
    {:ok, _} = Bbh.Content.update_block(pb, %{"shadow" => "true"})
    html = conn |> get(~p"/verein/karte") |> html_response(200)
    assert html =~ chrome
  end

  test "an inline media_card header aligns to the side opposite the image", %{conn: conn} do
    page = page_fixture(slug: "karte-titel", title: "Karte", status: "published")
    {:ok, _} = Bbh.Content.add_block(page, "media_card")
    [{pb, _block}] = Bbh.Content.load_blocks(Bbh.Content.get_page!(page.id))
    {:ok, _} = Bbh.Content.update_block(pb, %{"title" => "Ehrenmal", "subtitle" => "Untertitel"})

    # Default (title beside the image), image right: header is left-aligned, never right.
    html = conn |> get(~p"/verein/karte-titel") |> html_response(200)
    assert html =~ "Ehrenmal"
    assert html =~ "Untertitel"
    refute html =~ "text-right"

    # Image left: the inline header flips to right-aligned.
    {:ok, _} = Bbh.Content.update_block(pb, %{"image_position" => "left"})
    html = conn |> get(~p"/verein/karte-titel") |> html_response(200)
    assert html =~ "text-right"
  end

  test "the title-above toggle lifts the header out of the row and drops the alignment flip",
       %{conn: conn} do
    page = page_fixture(slug: "karte-oben", title: "Karte", status: "published")
    {:ok, _} = Bbh.Content.add_block(page, "media_card")
    [{pb, _block}] = Bbh.Content.load_blocks(Bbh.Content.get_page!(page.id))

    {:ok, _} =
      Bbh.Content.update_block(pb, %{
        "title" => "Ehrenmal",
        "image_position" => "left",
        "title_above" => "true"
      })

    html = conn |> get(~p"/verein/karte-oben") |> html_response(200)
    assert html =~ "Ehrenmal"
    # Full-width header + divider above the row …
    assert html =~ "mb-4"
    assert html =~ "h-px bg-base-300"
    # … and the alignment flip is off while the title is above, even with the image left.
    refute html =~ "text-right"
  end

  test "media_card caption and copyright show only when enabled", %{conn: conn} do
    page = page_fixture(slug: "karte-credit", title: "Karte", status: "published")
    {:ok, _} = Bbh.Content.add_block(page, "media_card")
    [{pb, _block}] = Bbh.Content.load_blocks(Bbh.Content.get_page!(page.id))
    # `description` drives the img alt text, so the caption itself only ever appears in
    # the (toggleable) figcaption — keeping the assertions unambiguous.
    upload =
      upload_fixture(%{description: "Denkmal", caption: "Foto von 1934", copyright: "BBH e.V."})

    {:ok, _} = Bbh.Content.update_block(pb, %{"image_id" => upload.id})

    # Default off: the media library's caption/copyright stay hidden.
    html = conn |> get(~p"/verein/karte-credit") |> html_response(200)
    refute html =~ "Foto von 1934"
    refute html =~ "BBH e.V."

    # Enabled: both appear beneath the image.
    {:ok, _} = Bbh.Content.update_block(pb, %{"show_credit" => "true"})
    html = conn |> get(~p"/verein/karte-credit") |> html_response(200)
    assert html =~ "Foto von 1934"
    assert html =~ "© BBH e.V."
  end

  describe "gallery block, Diashow layout" do
    setup %{conn: conn} do
      page = page_fixture(slug: "bilder", title: "Bilder", status: "published")
      {:ok, _} = Bbh.Content.add_block(page, "image_gallery")
      [{pb, gallery}] = Bbh.Content.load_blocks(Bbh.Content.get_page!(page.id))

      upload = upload_fixture(%{caption: "Antreten", copyright: "BBH e.V."})
      {:ok, _} = Bbh.Content.add_gallery_file(gallery, upload.id)

      html = fn attrs ->
        {:ok, _} = Bbh.Content.update_block(pb, attrs)
        conn |> get(~p"/verein/bilder") |> html_response(200)
      end

      %{html: html, gallery: gallery}
    end

    defp slide_images(markup) do
      markup
      |> LazyHTML.from_document()
      |> LazyHTML.query(".bbh-slideshow-slide img")
    end

    test "crops every slide to the chosen ratio instead of letterboxing it", %{html: html} do
      markup = html.(%{"layout" => "slideshow", "aspect_ratio" => "4:3"})
      img = slide_images(markup)

      # The frame the slides share. `object-cover` against it is what zooms a photo in
      # rather than leaving blank space beside it. Read off the slide's own <img>, not
      # the page — "object-cover" alone also matches the grid, the hero and the card.
      assert LazyHTML.attribute(img, "style") == ["aspect-ratio: 4/3"]
      assert [classes] = LazyHTML.attribute(img, "class")
      assert classes =~ "object-cover"
      # And the variant is cut to the same shape server-side, so the crop follows the
      # media item's focal point instead of the middle of the picture.
      assert [src] = LazyHTML.attribute(img, "src")
      assert src =~ "w=1600&h=1200"
    end

    test "a portrait ratio is honoured", %{html: html} do
      img = html.(%{"layout" => "slideshow", "aspect_ratio" => "9:16"}) |> slide_images()

      assert LazyHTML.attribute(img, "style") == ["aspect-ratio: 9/16"]
      assert [src] = LazyHTML.attribute(img, "src")
      assert src =~ "w=900&h=1600"
    end

    test "a variant is never asked for larger than the picture itself", %{
      html: html,
      gallery: gallery
    } do
      small = upload_fixture(%{filename: "klein.webp", width: 800, height: 600})
      {:ok, _} = Bbh.Content.add_gallery_file(gallery, small.id)

      markup = html.(%{"layout" => "slideshow", "aspect_ratio" => "16:9"})
      [_first, second] = LazyHTML.attribute(slide_images(markup), "src")

      # Upscaling an 800px club photo to 1600 buys nothing and costs bytes — the frame
      # is held by CSS regardless.
      assert second =~ "w=800&h=450"
    end

    test "shows the Bildunterschrift and copyright under the slide", %{html: html} do
      credit =
        html.(%{"layout" => "slideshow"})
        |> LazyHTML.from_document()
        |> LazyHTML.query(".bbh-slideshow-slide > figcaption")
        |> LazyHTML.text()

      # Queried inside the slide on purpose: the same two strings also ride along in the
      # trigger's `data-lightbox-*` attributes, so asserting on the whole page would
      # still pass with the credit line deleted. The grid hides these behind the
      # lightbox; a Diashow is the enlarged view, so the credit belongs on the page.
      assert credit =~ "Antreten"
      assert credit =~ "© BBH e.V."
    end

    test "autoplay is off unless the editor asked for it", %{html: html} do
      refute html.(%{"layout" => "slideshow"}) =~ "data-slideshow-interval"

      assert html.(%{"layout" => "slideshow", "autoplay" => "true"}) =~
               ~s(data-slideshow-interval="6000")
    end

    test "the first slide loads eagerly, the rest lazily", %{html: html, gallery: gallery} do
      {:ok, _} = Bbh.Content.add_gallery_file(gallery, upload_fixture(%{}).id)

      img = html.(%{"layout" => "slideshow"}) |> slide_images()

      # The visible slide is the gallery's LCP candidate; deferring it is the classic
      # way to lose a second on a page that leads with a Diashow.
      assert LazyHTML.attribute(img, "loading") == ["eager", "lazy"]
      assert LazyHTML.attribute(img, "fetchpriority") == ["high"]
    end

    test "controls appear only once there is more than one picture", %{
      html: html,
      gallery: gallery
    } do
      one = html.(%{"layout" => "slideshow"})
      refute one =~ "data-slideshow-next"
      refute one =~ "data-slideshow-dot"

      {:ok, _} = Bbh.Content.add_gallery_file(gallery, upload_fixture(%{}).id)
      two = html.(%{"layout" => "slideshow"})
      assert two =~ "data-slideshow-prev"
      assert two =~ "data-slideshow-next"
      # `aria-current={i == 0}` would render as a valueless attribute, which the spec
      # reads as "false" and the dot's CSS does not match — no dot would look active
      # until the visitor scrolled.
      assert two =~ ~s(aria-current="true")
      assert two =~ ~s(aria-current="false")
    end

    test "the grid layout keeps its square thumbnails and grows no controls", %{html: html} do
      markup = html.(%{"layout" => "grid"})

      assert markup =~ "aspect-square"
      refute markup =~ "data-slideshow"
      # The grid crops with a Tailwind class and emits no inline ratio at all.
      refute markup =~ "aspect-ratio:"
    end
  end

  test "GET an unknown page returns 404", %{conn: conn} do
    assert conn |> get(~p"/verein/gibt-es-nicht") |> response(404)
  end

  test "GET /verein/impressum is not reachable (legal pages are excluded)", %{conn: conn} do
    page_fixture(slug: "impressum", title: "Impressum", status: "published", show_in_menu: false)
    assert conn |> get(~p"/verein/impressum") |> response(404)
  end

  test "GET /impressum renders", %{conn: conn} do
    page_fixture(slug: "impressum", title: "Impressum", status: "published")
    assert conn |> get(~p"/impressum") |> html_response(200) =~ "Impressum"
  end
end
