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

  describe "person_list block" do
    setup %{conn: conn} do
      page = page_fixture(slug: "personen", title: "Personen", status: "published")
      {:ok, _} = Bbh.Content.add_block(page, "person_list")
      [{pb, _block}] = Bbh.Content.load_blocks(Bbh.Content.get_page!(page.id))

      html = fn attrs ->
        {:ok, _} = Bbh.Content.update_block(pb, attrs)
        conn |> get(~p"/verein/personen") |> html_response(200)
      end

      %{html: html, pb: pb}
    end

    defp person_cards(markup) do
      markup |> LazyHTML.from_document() |> LazyHTML.query(".bbh-person-card")
    end

    test "„Karten\" renders name, both date lines and the biography", %{html: html} do
      person_fixture(
        role: "vorstand",
        name: "Heinrich Meyer",
        birth_date: "1920 in Buterland",
        death_date: "1998 in Ahaus",
        biography: "<p>Gründungsmitglied und Fahnenträger.</p>"
      )

      # Queried inside the card, not across the page: the table renderer would also put
      # the name somewhere on the page, so a page-wide assertion would pass even with
      # the cards renderer never reached.
      text = html.(%{"display_style" => "cards"}) |> person_cards() |> LazyHTML.text()

      assert text =~ "Heinrich Meyer"
      assert text =~ "1920 in Buterland"
      assert text =~ "1998 in Ahaus"
      assert text =~ "Gründungsmitglied und Fahnenträger."
      # „†" announces as "dagger", so each date line carries a visually hidden label.
      assert text =~ "geboren"
      assert text =~ "gestorben"
    end

    test "a living person gets no death line at all", %{html: html} do
      person_fixture(role: "vorstand", name: "Karl Bauer", birth_date: "1954 in Ahaus")

      text = html.(%{"display_style" => "cards"}) |> person_cards() |> LazyHTML.text()

      assert text =~ "1954 in Ahaus"
      refute text =~ "†"
      refute text =~ "gestorben"
    end

    test "an emptied biography draws no divider above a blank box", %{html: html} do
      # Quill hands back "<p></p>" for an emptied editor — truthy, but nothing to show.
      person_fixture(role: "vorstand", name: "Ohne Text", biography: "<p></p>")

      cards = html.(%{"display_style" => "cards"}) |> person_cards()

      assert LazyHTML.query(cards, ".prose") |> Enum.empty?()
      assert LazyHTML.query(cards, ".h-px") |> Enum.empty?()
    end

    test "a biography that is only an image still renders", %{html: html} do
      # `Bbh.Html.sanitize/1` keeps `<img>` on purpose — that is what the media picker
      # inserts. Judging emptiness by text alone would drop a scanned document entirely.
      person_fixture(
        role: "vorstand",
        name: "Nur Bild",
        biography: ~s(<p><img src="/media/urkunde.webp"></p>)
      )

      cards = html.(%{"display_style" => "cards"}) |> person_cards()

      assert LazyHTML.query(cards, ".prose img") |> Enum.any?()
    end

    test "the people are marked up as a list", %{html: html} do
      person_fixture(role: "vorstand", name: "Eins")
      person_fixture(role: "oberst", name: "Zwei")

      markup = html.(%{"display_style" => "cards"})
      document = LazyHTML.from_document(markup)

      # A list, so assistive tech can announce how many people there are. And no heading
      # per person: the block's own `h3` is optional, so one here would skip a level.
      assert LazyHTML.query(document, "ul li.bbh-person-card") |> Enum.count() == 2
      assert LazyHTML.query(person_cards(markup), "h1, h2, h3, h4, h5, h6") |> Enum.empty?()
    end

    test "the portrait is cropped server-side so the focal point is honoured", %{html: html} do
      upload = upload_fixture(%{description: "Heinrich Meyer, 1988"})
      person_fixture(role: "vorstand", name: "Heinrich Meyer", portrait_id: upload.id)

      img = html.(%{"display_style" => "cards"}) |> person_cards() |> LazyHTML.query("img")

      # Both dimensions have to be requested: media_url/2 only carries the focal point on
      # a cover-crop URL, and that is what keeps a face in frame.
      assert [src] = LazyHTML.attribute(img, "src")
      assert src =~ "w=400&h=500"
      assert LazyHTML.attribute(img, "alt") == ["Heinrich Meyer, 1988"]
    end

    test "a person without a portrait gets the generic placeholder", %{html: html} do
      person_fixture(role: "vorstand", name: "Ohne Bild")

      cards = html.(%{"display_style" => "cards"}) |> person_cards()

      assert LazyHTML.query(cards, "img") |> Enum.empty?()
      assert LazyHTML.query(cards, "span.hero-user") |> Enum.any?()
    end

    test "„Tabelle\" still renders the table and no cards", %{html: html} do
      person_fixture(role: "vorstand", name: "Heinrich Meyer")

      markup = html.(%{"display_style" => "table"})

      assert markup =~ "Heinrich Meyer"
      assert markup |> LazyHTML.from_document() |> LazyHTML.query("table") |> Enum.count() == 1
      assert person_cards(markup) |> Enum.empty?()
    end

    test "an empty role filter lists everyone", %{html: html} do
      person_fixture(role: "vorstand", name: "Im Vorstand")
      person_fixture(role: "oberst", name: "Bei den Offizieren")

      # The editor's legend promises „Rollen (leer = alle)"; `p.role in ^[]` used to
      # match nobody, so an unfiltered block rendered an empty list.
      text = html.(%{"display_style" => "cards"}) |> person_cards() |> LazyHTML.text()

      assert text =~ "Im Vorstand"
      assert text =~ "Bei den Offizieren"
    end

    test "„Nur aktive Personen\" drops anyone with an „Amt bis\"", %{html: html} do
      person_fixture(role: "vorstand", name: "Amtierend")
      person_fixture(role: "vorstand", name: "Ehemalig", year_end: 1998)

      both = html.(%{"display_style" => "cards"}) |> person_cards() |> LazyHTML.text()
      assert both =~ "Amtierend"
      assert both =~ "Ehemalig"

      only_active =
        html.(%{"display_style" => "cards", "only_active" => "true"})
        |> person_cards()
        |> LazyHTML.text()

      assert only_active =~ "Amtierend"
      refute only_active =~ "Ehemalig"
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
