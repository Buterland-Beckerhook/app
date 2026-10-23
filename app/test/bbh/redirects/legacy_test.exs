defmodule Bbh.Redirects.LegacyTest do
  use Bbh.DataCase, async: true

  import Bbh.ContentFixtures
  import Bbh.CalendarFixtures

  alias Bbh.Redirects
  alias Bbh.Redirects.Legacy

  defp resolve(path), do: path |> Redirects.normalize_path() |> Legacy.resolve()

  describe "articles" do
    test "an old directory name with _ maps to the slugified article" do
      article_fixture(slug: "kein-biwak", date_published: ~U[2020-06-01 10:00:00Z])

      assert resolve("/aktuell/2020/kein_biwak/") == "/aktuell/2020/kein-biwak"
    end

    test "a percent-encoded ß maps to the transliterated slug" do
      article_fixture(slug: "pokal-und-preisschiessen", date_published: ~U[2019-06-01 10:00:00Z])

      assert resolve("/aktuell/2019/pokal-und-preisschie%C3%9Fen/") ==
               "/aktuell/2019/pokal-und-preisschiessen"
    end

    test "a Hugo alias maps to its article" do
      article_fixture(
        slug: "corona-update",
        date_published: ~U[2020-03-20 10:00:00Z],
        aliases: ["/aktuell/2020/corona/", "/aktuell/2020/Schützenfest_abgesagt"]
      )

      assert resolve("/aktuell/2020/corona") == "/aktuell/2020/corona-update"

      assert resolve("/aktuell/2020/sch%C3%BCtzenfest_abgesagt/") ==
               "/aktuell/2020/corona-update"
    end

    test "unpublished, missing and same-path articles do not redirect" do
      article_fixture(slug: "entwurf", status: "draft", date_published: ~U[2020-06-01 10:00:00Z])

      article_fixture(
        slug: "versteckt",
        status: "draft",
        date_published: ~U[2020-06-01 10:00:00Z],
        aliases: ["/aktuell/2020/alt"]
      )

      assert resolve("/aktuell/2020/entwurf") == nil
      assert resolve("/aktuell/2020/gibt_es_nicht") == nil
      assert resolve("/aktuell/2020/alt") == nil
    end

    test "section, pagination and feed URLs" do
      assert resolve("/aktuell/2023/") == "/aktuell"
      assert resolve("/aktuell/page/3/") == "/aktuell?seite=3"
      assert resolve("/aktuell/page/1/") == "/aktuell"
      assert resolve("/aktuell/index.xml") == "/aktuell"
      assert resolve("/index.xml") == "/aktuell"
    end
  end

  describe "events" do
    test "an old file name with _ maps to the slugified event" do
      event_fixture(slug: "reinigung-vereinsbezirk", starts_at: ~U[2023-04-15 08:00:00Z])

      assert resolve("/termine/2023/reinigung_vereinsbezirk/") ==
               "/termine/2023/reinigung-vereinsbezirk"
    end

    test "the per-event calendar file maps to event.ics" do
      event_fixture(slug: "biwak", starts_at: ~U[2023-05-13 14:00:00Z])

      assert resolve("/termine/2023/biwak/index.ics") == "/termine/2023/biwak/event.ics"
    end

    test "year sections and year calendars" do
      assert resolve("/termine/2023/") == "/termine?jahr=2023"
      assert resolve("/termine/2023/index.ics") == "/termine/abo.ics"
    end

    test "an unknown event does not redirect" do
      assert resolve("/termine/2023/gibt_es_nicht") == nil
      assert resolve("/termine/2023/gibt_es_nicht/index.ics") == nil
    end
  end

  describe "other Hugo URLs" do
    test "privacy page, taxonomies" do
      assert resolve("/datenschutzerklaerung/") == "/datenschutz"
      assert resolve("/tags/") == "/aktuell"
      assert resolve("/categories") == "/aktuell"
      assert resolve("/tags/kaiser-schiessen/") == "/suche?q=kaiser+schiessen"
    end

    test "anything else is nil" do
      assert resolve("/verein/vorstand/kontakt") == nil
      assert resolve("/aktuell/abcd/x") == nil
    end
  end
end
