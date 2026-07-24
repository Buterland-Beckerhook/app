defmodule Bbh.SearchTest do
  use Bbh.DataCase, async: true
  use Oban.Testing, repo: Bbh.Repo

  alias Bbh.{Content, Search}

  import Bbh.ContentFixtures

  defp urls(result), do: Enum.map(result.entries, & &1.url)

  describe "reindex_all/0 + search/3 visibility" do
    test "finds a published article and excludes drafts" do
      article_fixture(%{
        status: "published",
        title: "Sommerfest im Buterland",
        slug: "sommerfest",
        body: "<p>Ein rauschendes Zeltlagerfest.</p>"
      })

      article_fixture(%{
        status: "draft",
        title: "Geheimes Zeltlagerfest",
        slug: "geheim"
      })

      Search.reindex_all()

      result = Search.search("Zeltlagerfest")

      assert result.total == 1
      assert [%{source_type: "article", title: "Sommerfest im Buterland"}] = result.entries
    end

    test "excludes throne-only (no_article) and not-yet-published articles" do
      article_fixture(%{title: "Nur Thron", no_article: true, body: "<p>Kranzniederlegung</p>"})

      article_fixture(%{
        title: "Zukunft",
        slug: "zukunft",
        body: "<p>Kranzniederlegung</p>",
        date_published: DateTime.add(DateTime.utc_now(), 7, :day) |> DateTime.truncate(:second)
      })

      Search.reindex_all()

      assert Search.search("Kranzniederlegung").total == 0
    end

    test "throne court names make the parent article findable" do
      article = article_fixture(%{title: "Königsschuss", slug: "koenigsschuss"})
      throne_fixture(%{article: article, king: "Xaverius Wunderlich", queen: "Adelheid"})

      Search.reindex_all()

      result = Search.search("Wunderlich")
      assert "/aktuell/#{article.year}/koenigsschuss" in urls(result)
    end

    test "indexes a published /verein page's block text" do
      page = page_fixture(%{title: "Chronik", slug: "chronik"})
      {:ok, pb} = Content.add_block(page, "richtext")
      {:ok, _} = Content.update_block(pb, %{body: "<p>Die Gründungsversammlung von 1899.</p>"})

      Search.reindex_all()

      result = Search.search("Gründungsversammlung")
      assert "/verein/chronik" in urls(result)
    end
  end

  describe "search/3 querying" do
    test "German stemming matches singular/plural" do
      article_fixture(%{title: "Der König", slug: "koenig", body: "<p>Lang lebe der König.</p>"})
      Search.reindex_all()

      # Plural query term stems to the same root as the indexed singular.
      assert Search.search("Könige").total == 1
    end

    test "ranks a title match above a body-only match" do
      article_fixture(%{title: "Vogelschießen 2026", slug: "titel", body: "<p>Ohne Bezug.</p>"})

      article_fixture(%{
        title: "Nachbericht",
        slug: "body",
        body: "<p>Das Vogelschießen war ein Erfolg.</p>"
      })

      Search.reindex_all()

      result = Search.search("Vogelschießen")
      assert [first, second] = result.entries
      assert first.title == "Vogelschießen 2026"
      assert second.title == "Nachbericht"
    end

    test "blank query returns an empty result with the pagination shape" do
      result = Search.search("   ")
      assert result == %{entries: [], page: 1, per_page: 20, total: 0, total_pages: 1}
    end

    test "a content write enqueues one debounced, deduplicated reindex" do
      article = article_fixture()
      assert_enqueued(worker: Bbh.Workers.SearchReindexer)

      # A second change within the unique window coalesces onto the pending job.
      {:ok, _} = Content.update_article(article, %{title: "Geändert"})
      assert length(all_enqueued(worker: Bbh.Workers.SearchReindexer)) == 1
    end

    test "paginates results" do
      for i <- 1..25 do
        article_fixture(%{title: "Ummeldung #{i}", slug: "ummeldung-#{i}", body: "<p>Termin</p>"})
      end

      Search.reindex_all()

      page1 = Search.search("Ummeldung", 1, 20)
      page2 = Search.search("Ummeldung", 2, 20)

      assert page1.total == 25
      assert page1.total_pages == 2
      assert length(page1.entries) == 20
      assert length(page2.entries) == 5
    end
  end
end
