defmodule BbhWeb.PageContentControllerTest do
  use BbhWeb.ConnCase, async: true

  import Bbh.ContentFixtures
  import BbhWeb.MediaUrlHelpers
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

  test "a draft page is hidden from anonymous visitors (404)", %{conn: conn} do
    page_fixture(slug: "geheim", title: "Geheime Seite", status: "draft")
    assert conn |> get(~p"/verein/geheim") |> response(404)
  end

  describe "draft page preview for editors" do
    setup :register_and_log_in_admin

    test "previews a draft page with a banner", %{conn: conn} do
      page_fixture(slug: "geheim", title: "Geheime Seite", status: "draft")
      html = conn |> get(~p"/verein/geheim") |> html_response(200)
      assert html =~ "Geheime Seite"
      assert html =~ "Vorschau"
    end

    test "lists draft pages with a badge on the Verein overview", %{conn: conn} do
      page_fixture(slug: "geheim", title: "Geheime Seite", status: "draft")
      html = conn |> get(~p"/verein") |> html_response(200)
      assert html =~ "Geheime Seite"
      assert html =~ "Entwurf"
    end
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

  describe "gallery block, grid in Originalformat" do
    setup %{conn: conn} do
      page = page_fixture(slug: "raster", title: "Raster", status: "published")
      {:ok, _} = Bbh.Content.add_block(page, "image_gallery")
      [{pb, gallery}] = Bbh.Content.load_blocks(Bbh.Content.get_page!(page.id))

      add = fn attrs ->
        upload = upload_fixture(attrs)
        {:ok, _} = Bbh.Content.add_gallery_file(gallery, upload.id)
      end

      html = fn attrs ->
        {:ok, _} = Bbh.Content.update_block(pb, attrs)
        conn |> get(~p"/verein/raster") |> html_response(200)
      end

      %{add: add, html: html}
    end

    defp items(markup) do
      markup |> LazyHTML.from_document() |> LazyHTML.query(".bbh-justified-item")
    end

    test "square stays the default crop", %{add: add, html: html} do
      add.(%{width: 3000, height: 2000})
      markup = html.(%{"title" => "Antreten"})

      refute markup =~ "bbh-justified"
      assert markup =~ "aspect-square"
    end

    test "each item carries its own ratio and a width-only variant", %{add: add, html: html} do
      add.(%{width: 3000, height: 2000})
      add.(%{width: 2000, height: 3000})
      add.(%{width: 4000, height: 3000})

      markup = html.(%{"grid_fit" => "original"})
      list = items(markup)

      assert LazyHTML.attribute(list, "style") == ["--r: 1.5", "--r: 0.6667", "--r: 1.3333"]
      # 2 × 14rem rows × ratio, rounded up to 100px; no height, so no crop server-side.
      assert ["/media/" <> a, _, _] = list |> LazyHTML.query("img") |> LazyHTML.attribute("src")
      assert unsigned(a) =~ ~r/\?w=700\z/
      # More than two pictures: the filler keeps the last row at row height.
      assert markup =~ "bbh-justified-fill"
    end

    test "a picture without dimensions counts as square", %{add: add, html: html} do
      add.(%{width: nil, height: nil})

      assert html.(%{"grid_fit" => "original"}) |> items() |> LazyHTML.attribute("style") ==
               ["--r: 1"]
    end

    test "one or two pictures fill the width; never above the original", %{
      add: add,
      html: html
    } do
      add.(%{width: 800, height: 600})
      markup = html.(%{"grid_fit" => "original"})

      refute markup =~ "bbh-justified-fill"
      assert [src] = markup |> items() |> LazyHTML.query("img") |> LazyHTML.attribute("src")
      assert unsigned(src) =~ ~r/\?w=800\z/
    end

    test "the title is the caption below the pictures", %{add: add, html: html} do
      add.(%{width: 3000, height: 2000})

      for fit <- ~w(original square) do
        markup = html.(%{"title" => "Die ersten Jungschützen", "grid_fit" => fit})
        doc = LazyHTML.from_document(markup)

        assert doc |> LazyHTML.query("figure > figcaption.bbh-fig-caption") |> LazyHTML.text() ==
                 "Die ersten Jungschützen"

        assert doc |> LazyHTML.query("figure > figcaption:last-child") |> LazyHTML.text() ==
                 "Die ersten Jungschützen"
      end
    end
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

  describe "trophy_table block" do
    import Bbh.ClubFixtures

    setup %{conn: conn} do
      page = page_fixture(slug: "pokale", title: "Pokale", status: "published")
      {:ok, _} = Bbh.Content.add_block(page, "trophy_table")
      [{pb, _block}] = Bbh.Content.load_blocks(Bbh.Content.get_page!(page.id))

      html = fn attrs ->
        {:ok, _} = Bbh.Content.update_block(pb, attrs)
        conn |> get(~p"/verein/pokale") |> html_response(200)
      end

      %{html: html}
    end

    defp trophy_table(markup) do
      markup |> LazyHTML.from_document() |> LazyHTML.query(".bbh-trophy-table")
    end

    test "renders year × trophy with rings, a dash for a gap, and the records", %{html: html} do
      t = trophy_fixture(name: "Schützenpokal", since: 1965, description: "Für alle.")
      for y <- [2022, 2023, 2024], do: trophy_win_fixture(trophy: t, year: y, winner: "Anna")
      trophy_win_fixture(trophy: t, year: 2026, winner: "Simon Sell", rings: 29)

      table = html.(%{"show_records" => "true", "show_descriptions" => "true"}) |> trophy_table()
      text = LazyHTML.text(table)

      assert text =~ "Schützenpokal"
      assert text =~ "Simon Sell (29)"
      # 2025 had no winner: the row is there, with a dash.
      assert text =~ "2025"
      dashes = LazyHTML.query(table, ~s(table [aria-label="kein Sieger bekannt"]))
      assert Enum.count(dashes) == 1
      assert text =~ "Rekordsieger"
      assert text =~ "Anna (3×)"
      assert text =~ "seit 1965"
      assert text =~ "Für alle."
    end

    test "hides records and descriptions when switched off", %{html: html} do
      t = trophy_fixture(name: "Königspokal", description: "Nur Könige.")
      for y <- [2001, 2002, 2003], do: trophy_win_fixture(trophy: t, year: y, winner: "Anna")

      text =
        html.(%{"show_records" => "false", "show_descriptions" => "false"})
        |> trophy_table()
        |> LazyHTML.text()

      assert text =~ "Anna"
      refute text =~ "Rekordsieger"
      refute text =~ "Nur Könige."
    end

    test "shows the latest year's winners as cards, none for a trophy not won that year",
         %{html: html} do
      s = trophy_fixture(name: "Schützenpokal", sort_order: 1)
      b = trophy_fixture(name: "Biwakpokal", sort_order: 2)
      trophy_win_fixture(trophy: s, year: 2025, winner: "Bernd Verst", rings: 30)
      trophy_win_fixture(trophy: b, year: 2025, winner: "Anna")
      trophy_win_fixture(trophy: s, year: 2026, winner: "Simon Sell", rings: 29)

      section = html.(%{}) |> trophy_table()
      cards = LazyHTML.query(section, ".bbh-trophy-card")

      assert LazyHTML.text(section) =~ "Die Sieger 2026"
      assert Enum.count(cards) == 1
      assert LazyHTML.text(cards) =~ "Simon Sell"
      assert LazyHTML.text(cards) =~ "29 Ringe"
      refute LazyHTML.text(cards) =~ "Biwakpokal"
      refute LazyHTML.text(cards) =~ "Bernd Verst"
    end

    test "after years without a shooting, the cards show the last year that had one",
         %{html: html} do
      t = trophy_fixture(name: "Schützenpokal")
      trophy_win_fixture(trophy: t, year: 2020, winner: "Heiko Oude Lansink")

      # 2021/22 (Corona) would only exist as rows if a later year had winners.
      section = html.(%{}) |> trophy_table()

      assert LazyHTML.text(section) =~ "Die Sieger 2020"
      assert section |> LazyHTML.query(".bbh-trophy-card") |> Enum.count() == 1
    end

    test "offers the table and one view per trophy, starting at its first winner",
         %{html: html} do
      s = trophy_fixture(name: "Schützenpokal", sort_order: 1)
      b = trophy_fixture(name: "Biwakpokal", sort_order: 2)
      trophy_win_fixture(trophy: s, year: 2001, winner: "Anna")
      trophy_win_fixture(trophy: b, year: 2010, winner: "Berta")
      trophy_win_fixture(trophy: b, year: 2012, winner: "Carla")

      section = html.(%{}) |> trophy_table()
      tabs = LazyHTML.query(section, ".bbh-tab")
      panels = LazyHTML.query(section, ".bbh-tab-panel")

      assert tabs |> Enum.map(&LazyHTML.text/1) |> Enum.map(&String.trim/1) ==
               ["Alle Pokale", "Schützenpokal", "Biwakpokal"]

      # One radio group, the table checked by default.
      radios = LazyHTML.query(section, ~s(input[type="radio"]))
      assert radios |> LazyHTML.attribute("name") |> Enum.uniq() |> length() == 1
      assert LazyHTML.query(section, ".bbh-tab-all input[checked]") |> Enum.count() == 1

      biwak = panels |> Enum.at(2) |> LazyHTML.text()
      assert biwak =~ "Carla"
      assert biwak =~ "2011"
      # Years before its first winner are left out of the trophy's own list.
      refute biwak =~ "2009"
    end

    test "renders nothing without winners", %{html: html} do
      trophy_fixture()
      assert html.(%{}) |> trophy_table() |> Enum.empty?()
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
        birth_date: ~D[1920-03-01],
        birth_place: "Buterland",
        death_date: ~D[1998-11-07],
        death_place: "Ahaus",
        honorary_since: 1978,
        biography: "<p>Gründungsmitglied und Fahnenträger.</p>"
      )

      # Queried inside the card, not across the page: the table renderer would also put
      # the name somewhere on the page, so a page-wide assertion would pass even with
      # the cards renderer never reached.
      text = html.(%{"display_style" => "cards"}) |> person_cards() |> LazyHTML.text()

      assert text =~ "Heinrich Meyer"
      assert text =~ "1. März 1920 in Buterland"
      assert text =~ "7. November 1998 in Ahaus"
      assert text =~ "Ehrenmitglied seit 1978"
      assert text =~ "Gründungsmitglied und Fahnenträger."
      # „†" announces as "dagger", so each date line carries a visually hidden label.
      assert text =~ "geboren"
      assert text =~ "gestorben"
    end

    test "a living person gets no death line at all", %{html: html} do
      person_fixture(role: "vorstand", name: "Karl Bauer", birth_date: ~D[1954-09-04])

      text = html.(%{"display_style" => "cards"}) |> person_cards() |> LazyHTML.text()

      # No place stored: the date stands alone, without a dangling „in".
      assert text =~ "4. September 1954"
      refute text =~ "1954 in"
      refute text =~ "†"
      refute text =~ "gestorben"
    end

    test "a place with its own preposition is printed as is", %{html: html} do
      person_fixture(
        role: "vorstand",
        name: "Anton Sundag",
        birth_date: ~D[1847-05-06],
        birth_place: "im Kirchspiel Epe"
      )

      text = html.(%{"display_style" => "cards"}) |> person_cards() |> LazyHTML.text()

      assert text =~ "6. Mai 1847 im Kirchspiel Epe"
      refute text =~ "in im"
    end

    test "the unknown appointment year is not shown", %{html: html} do
      person_fixture(role: "vorstand", name: "Willi Hoff", honorary_since: 1900)

      text = html.(%{"display_style" => "cards"}) |> person_cards() |> LazyHTML.text()

      refute text =~ "Ehrenmitglied seit"
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
    page_fixture(slug: "impressum", title: "Impressum", status: "published", placement: "system")
    assert conn |> get(~p"/verein/impressum") |> response(404)
  end

  test "GET /impressum renders", %{conn: conn} do
    page_fixture(slug: "impressum", title: "Impressum", status: "published")
    assert conn |> get(~p"/impressum") |> html_response(200) =~ "Impressum"
  end

  describe "unlisted pages (/seite/:slug)" do
    test "renders a published unlisted page", %{conn: conn} do
      page_fixture(slug: "anfahrt", title: "Anfahrt", placement: "unlisted")
      html = conn |> get(~p"/seite/anfahrt") |> html_response(200)
      assert html =~ "Anfahrt"
    end

    test "is neither listed under nor served from /verein", %{conn: conn} do
      page_fixture(slug: "anfahrt", title: "Anfahrt zum Festplatz", placement: "unlisted")

      refute conn |> get(~p"/verein") |> html_response(200) =~ "Anfahrt zum Festplatz"
      assert conn |> get(~p"/verein/anfahrt") |> response(404)
    end

    test "menu and system pages are not served under /seite", %{conn: conn} do
      page_fixture(slug: "ueber-uns", placement: "menu")
      page_fixture(slug: "impressum", placement: "system")

      assert conn |> get(~p"/seite/ueber-uns") |> response(404)
      assert conn |> get(~p"/seite/impressum") |> response(404)
    end

    test "a draft unlisted page is 404 for anonymous visitors", %{conn: conn} do
      page_fixture(slug: "entwurf", placement: "unlisted", status: "draft")
      assert conn |> get(~p"/seite/entwurf") |> response(404)
    end

    test "noindex sets X-Robots-Tag, otherwise it is absent", %{conn: conn} do
      page_fixture(slug: "versteckt", placement: "unlisted", noindex: true)
      page_fixture(slug: "offen", placement: "unlisted")

      assert get_resp_header(get(conn, ~p"/seite/versteckt"), "x-robots-tag") == [
               "noindex, nofollow"
             ]

      assert get_resp_header(get(conn, ~p"/seite/offen"), "x-robots-tag") == []
    end

    test "noindex also applies to menu pages", %{conn: conn} do
      page_fixture(slug: "intern", placement: "menu", noindex: true)
      conn = get(conn, ~p"/verein/intern")
      assert html_response(conn, 200)
      assert get_resp_header(conn, "x-robots-tag") == ["noindex, nofollow"]
    end
  end

  describe "unlisted draft preview for editors" do
    setup :register_and_log_in_admin

    test "previews a draft unlisted page with a banner", %{conn: conn} do
      page_fixture(
        slug: "entwurf",
        title: "Entwurfsseite",
        placement: "unlisted",
        status: "draft"
      )

      html = conn |> get(~p"/seite/entwurf") |> html_response(200)
      assert html =~ "Entwurfsseite"
      assert html =~ "Vorschau"
    end
  end
end
