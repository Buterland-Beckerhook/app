defmodule Bbh.Workers.ArticlePublishNotifierTest do
  use Bbh.DataCase, async: true

  import Bbh.ContentFixtures

  alias Bbh.Content
  alias Bbh.Content.Article
  alias Bbh.Workers.ArticlePublishNotifier

  defp from_now(n), do: Bbh.Time.now() |> DateTime.add(n, :day) |> DateTime.truncate(:second)

  test "only due, published, non-throne, unnotified articles are pending" do
    due = article_fixture(status: "published", date_published: from_now(-1))
    _future = article_fixture(status: "published", date_published: from_now(2))
    _draft = article_fixture(status: "draft", date_published: from_now(-1))
    _throne = article_fixture(no_article: true, status: "published", date_published: from_now(-1))

    assert Enum.map(Content.articles_pending_notification(), & &1.id) == [due.id]
  end

  test "perform notifies each due article once and marks it" do
    due = article_fixture(status: "published", date_published: from_now(-1))
    future = article_fixture(status: "published", date_published: from_now(2))

    assert :ok = ArticlePublishNotifier.perform(%Oban.Job{})

    # Marked, so no longer pending; a second run is a no-op.
    assert Repo.get(Article, due.id).notified_at
    assert Content.articles_pending_notification() == []
    assert :ok = ArticlePublishNotifier.perform(%Oban.Job{})

    # The future-dated article is untouched until its date passes.
    refute Repo.get(Article, future.id).notified_at
  end
end
