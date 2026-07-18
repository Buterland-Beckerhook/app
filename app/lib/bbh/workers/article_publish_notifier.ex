defmodule Bbh.Workers.ArticlePublishNotifier do
  @moduledoc """
  Sends the "Neuer Artikel" web-push once an article's publish date has passed.

  Runs on a cron (every five minutes) so scheduled ("vorveröffentlichte")
  articles get their push when their `date_published` arrives, and immediate
  publishes are picked up on the next tick. `notify/1` is also called directly
  (off-request) by the article form for an instant push when publishing now.

  Idempotent: each article is pushed at most once, guarded by
  `Article.notified_at`.
  """
  use Oban.Worker, queue: :notifications, max_attempts: 3

  alias Bbh.Content
  alias Bbh.Content.Article

  @impl Oban.Worker
  def perform(_job) do
    for article <- Content.articles_pending_notification(), do: notify(article)
    :ok
  end

  @doc "Push the publish notification for one article and mark it as notified."
  def notify(%Article{} = article) do
    # Mark first so a retry after a crash mid-send doesn't double-notify.
    {:ok, article} = Content.mark_article_notified(article)

    url = BbhWeb.Endpoint.url() <> "/aktuell/#{article.year}/#{article.slug}"
    Bbh.Notifications.notify("news", %{title: "Neuer Artikel", body: article.title, url: url})

    :ok
  end
end
