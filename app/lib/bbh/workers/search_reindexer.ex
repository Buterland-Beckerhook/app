defmodule Bbh.Workers.SearchReindexer do
  @moduledoc """
  Rebuilds the full-text search index (`search_documents`) from current public
  content.

  Runs on a cron (every 15 minutes) so newly published articles, events and
  pages become searchable without any per-record bookkeeping. The rebuild is a
  cheap, idempotent clear-and-insert (small data set), which makes it
  self-healing: a missed or crashed run is fully repaired by the next tick.
  """
  use Oban.Worker, queue: :default, max_attempts: 3

  @impl Oban.Worker
  def perform(_job), do: Bbh.Search.reindex_all()
end
