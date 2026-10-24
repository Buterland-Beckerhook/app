defmodule BbhWeb.EventBlockTest do
  use BbhWeb.ConnCase, async: true

  import Bbh.CalendarFixtures
  import Bbh.ContentFixtures

  alias Bbh.Content

  setup %{conn: conn} do
    festival =
      festival_fixture(title: "Schützenfest Demo", body: "<p>Das ganze Dorf feiert.</p>")

    programme_item_fixture(festival, title: "Antreten", slug: "antreten")

    programme_item_fixture(festival,
      title: "Kinderbelustigung",
      status: "canceled",
      starts_at: ~U[2030-07-21 14:00:00Z],
      ends_at: ~U[2030-07-21 16:00:00Z]
    )

    programme_item_fixture(festival, title: "Geheimer Entwurf", status: "draft")

    article = article_fixture(title: "Einladung zum Schützenfest", body: nil)
    {:ok, pb} = Content.add_block(article, "event")

    html = fn attrs ->
      {:ok, _} = Content.update_block(pb, attrs)
      conn |> get(~p"/aktuell/#{article.year}/#{article.slug}") |> html_response(200)
    end

    %{festival: festival, html: html, pb: pb}
  end

  test "shows the festival with its visible programme, read live", %{festival: f, html: html} do
    markup = html.(%{event_id: f.id})

    assert markup =~ "Schützenfest Demo"
    assert markup =~ "Antreten"
    assert markup =~ "Kinderbelustigung"
    assert markup =~ "Abgesagt"
    refute markup =~ "Geheimer Entwurf"
    # Off by default: the article usually says it in its own words.
    refute markup =~ "Das ganze Dorf feiert."
    assert markup =~ ~s(href="/termine/#{f.year}/#{f.slug}")

    # The festival page owns the item anchors; the article must not claim them.
    refute markup =~ ~s(id="antreten")

    programme_item_fixture(f, title: "Nachgetragen")
    assert html.(%{}) =~ "Nachgetragen"
  end

  test "the switches hide header and programme and show the description",
       %{festival: f, html: html} do
    markup = html.(%{event_id: f.id, show_header: false, show_programme: false, show_body: true})

    refute markup =~ "Schützenfest Demo"
    refute markup =~ "Antreten"
    assert markup =~ "Das ganze Dorf feiert."
  end

  test "renders nothing while the event is not public", %{festival: f, html: html} do
    {:ok, _} = Bbh.Calendar.update_event(f, %{status: "draft"})

    markup = html.(%{event_id: f.id})
    refute markup =~ "Antreten"
    refute markup =~ "Zum Termin"
  end

  test "an event deleted later leaves an empty block", %{festival: f, html: html, pb: pb} do
    html.(%{event_id: f.id})
    {:ok, _} = Bbh.Calendar.delete_event(f)

    assert Content.get_block(pb).event_id == nil
    refute html.(%{}) =~ "Zum Termin"
  end

  test "a programme item cannot be chosen", %{festival: f, pb: pb} do
    [item | _] = Bbh.Calendar.list_children(f)

    assert {:error, changeset} = Content.update_block(pb, %{event_id: item.id})
    assert changeset.errors[:event_id]
  end
end
