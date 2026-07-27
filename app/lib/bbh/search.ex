defmodule Bbh.Search do
  @moduledoc """
  Public full-text search over all public content.

  Backed by a single `search_documents` table (a unified index) whose
  `search_vector` is a Postgres-generated `tsvector` (German config, title
  weighted `A`, content `B`). `reindex_all/0` rebuilds the whole index from the
  published articles, public events and reachable pages; it is cheap (small data
  set) and idempotent, and runs on a cron via `Bbh.Workers.SearchReindexer`.

  Queries use `websearch_to_tsquery` so visitor input ("König", `"exact phrase"`,
  `-minus`, `or`) is parsed safely and never interpolated into SQL. The German
  config gives stemming (Singular/Plural) and stop-word removal for free.
  """
  import Ecto.Query

  alias Bbh.Repo
  alias Bbh.Content
  alias Bbh.Calendar.Event
  alias Bbh.Content.{Article, Blocks, Page}
  alias Bbh.Search.SearchDocument

  @per_page 20

  ## Query

  @doc """
  Search the index for `q`, paginated. Returns the same map shape as the public
  listing pages (`%{entries, page, per_page, total, total_pages}`) so the
  `<.pagination>` component works unchanged. A blank query yields an empty result.
  """
  def search(q, page \\ 1, per_page \\ @per_page)

  def search(q, page, per_page) when is_binary(q) do
    case String.trim(q) do
      "" -> empty_result(page, per_page)
      term -> run_search(term, page, per_page)
    end
  end

  def search(_q, page, per_page), do: empty_result(page, per_page)

  defp run_search(term, page, per_page) do
    page = max(page, 1)

    base =
      from d in SearchDocument,
        where: fragment("? @@ websearch_to_tsquery('german', ?)", d.search_vector, ^term)

    total = Repo.aggregate(base, :count, :id)

    entries =
      base
      |> order_by([d],
        desc: fragment("ts_rank(?, websearch_to_tsquery('german', ?))", d.search_vector, ^term),
        desc: d.document_date
      )
      |> limit(^per_page)
      |> offset(^((page - 1) * per_page))
      |> select_merge([d], %{
        # Neutral sentinel markers, not real tags: the content is plain text
        # that may contain "<"/"&", so the template HTML-escapes the whole
        # snippet and only then swaps these markers for <mark> (XSS-safe).
        headline:
          fragment(
            "ts_headline('german', ?, websearch_to_tsquery('german', ?), 'StartSel=@@M@@,StopSel=@@E@@,MaxFragments=1,MaxWords=40,MinWords=15')",
            d.content,
            ^term
          )
      })
      |> Repo.all()

    %{
      entries: entries,
      page: page,
      per_page: per_page,
      total: total,
      total_pages: max(ceil(total / per_page), 1)
    }
  end

  defp empty_result(page, per_page) do
    %{entries: [], page: max(page, 1), per_page: per_page, total: 0, total_pages: 1}
  end

  ## Reindexing

  @doc """
  Enqueue a full reindex after a content change, so edits show up in search
  without waiting for the cron. Debounced (`schedule_in`) and deduplicated
  (`unique`) so a burst of saves — e.g. an article plus its throne and images —
  collapses into a single rebuild.
  """
  def enqueue_reindex do
    %{}
    |> Bbh.Workers.SearchReindexer.new(
      schedule_in: 5,
      unique: [period: 60, states: [:available, :scheduled]]
    )
    |> Oban.insert()
  end

  @doc """
  Pass a write result straight through, enqueuing a reindex when it succeeded.
  Lets context write functions opt in with a single trailing pipe.
  """
  def reindex_after({:ok, _} = result) do
    enqueue_reindex()
    result
  end

  def reindex_after(result), do: result

  @doc """
  Rebuild the whole search index from currently public content. Runs in a
  transaction (clear + bulk insert) so a search never sees a half-built index.
  """
  def reindex_all do
    now = Bbh.Time.now()
    rows = article_docs(now) ++ event_docs() ++ page_docs()

    ts = DateTime.utc_now(:second)

    rows =
      Enum.map(rows, fn row ->
        Map.merge(row, %{id: Ecto.UUID.generate(), inserted_at: ts, updated_at: ts})
      end)

    Repo.transaction(fn ->
      Repo.delete_all(SearchDocument)

      rows
      |> Enum.chunk_every(200)
      |> Enum.each(&Repo.insert_all(SearchDocument, &1))
    end)

    :ok
  end

  # Published, real articles whose publish date has passed (same rule as the
  # public /aktuell listing). Throne names ride along in the article's content.
  defp article_docs(now) do
    Repo.all(
      from a in Article,
        where: a.status == "published" and a.no_article == false and a.date_published <= ^now,
        preload: [:throne]
    )
    |> Enum.map(fn a ->
      %{
        source_type: "article",
        source_id: a.id,
        title: a.title,
        url: "/aktuell/#{a.year}/#{a.slug}",
        content:
          join(
            [a.subtitle, a.author, blocks_text(a)] ++
              a.tags ++ a.aliases ++ throne_parts(a.throne)
          ),
        document_date: a.date_published
      }
    end)
  end

  defp throne_parts(nil), do: []

  defp throne_parts(t) do
    [t.king_title, t.king, t.queen, t.moh1, t.moh2, t.loh1, t.loh2, t.cupbearer, t.courtmarshal]
  end

  # Public events only (published, publicly announced, not on an internal
  # calendar) — the same predicate as Bbh.Calendar's public listings.
  defp event_docs do
    Repo.all(
      from e in Event,
        where: e.status == "published" and e.announce == true and is_nil(e.calendar)
    )
    |> Enum.map(fn e ->
      %{
        source_type: "event",
        source_id: e.id,
        title: e.title,
        url: "/termine/#{e.year}/#{e.slug}",
        content: Bbh.Html.to_text(e.body),
        document_date: e.starts_at
      }
    end)
  end

  # Publicly reachable pages: the menu-reachable /verein/* tree plus the two
  # legal pages that have their own top-level routes.
  defp page_docs, do: menu_docs() ++ legal_docs()

  defp menu_docs do
    Content.list_menu_pages()
    |> Enum.flat_map(fn root -> page_tree_docs(root, "/verein/" <> root.slug) end)
  end

  defp page_tree_docs(page, path) do
    children =
      page.id
      |> Content.list_child_pages()
      |> Enum.flat_map(fn child -> page_tree_docs(child, path <> "/" <> child.slug) end)

    [page_doc(page, path) | children]
  end

  defp legal_docs do
    ~w(impressum datenschutz)
    |> Enum.map(fn slug -> {slug, Repo.get_by(Page, slug: slug, status: "published")} end)
    |> Enum.filter(fn {_slug, page} -> page end)
    |> Enum.map(fn {slug, page} -> page_doc(page, "/" <> slug) end)
  end

  defp page_doc(page, path) do
    %{
      source_type: "page",
      source_id: page.id,
      title: page.title,
      url: path,
      content: blocks_text(page),
      document_date: page.updated_at
    }
  end

  # Joined plain text of an owner's content blocks (page or article), for the index.
  defp blocks_text(owner) do
    owner
    |> Content.load_blocks()
    |> Enum.map(fn {_pb, block} -> block_text(block) end)
    |> join()
  end

  defp block_text(%Blocks.RichText{body: body}), do: Bbh.Html.to_text(body)
  defp block_text(%Blocks.Alert{body: body}), do: Bbh.Html.to_text(body)

  defp block_text(%Blocks.MediaCard{} = b),
    do: join([b.title, b.subtitle, Bbh.Html.to_text(b.body)])

  defp block_text(%Blocks.ImageGallery{} = b), do: join([b.title, gallery_files_text(b)])
  # Only the title, deliberately. The „Karten" style publishes names, dates and biographies,
  # but those live on `people` — indexing them here would make a page's document stale on
  # every person edit, and `Bbh.Club` has no `reindex_after/1` hook the way
  # `Content.update_block/2` does. Wiring that up is the price of making people searchable.
  defp block_text(%Blocks.PersonList{title: title}), do: title || ""
  defp block_text(_), do: ""

  # A gallery file's searchable text lives on its media item (caption/title/copyright),
  # which is where it is edited — the file row itself only carries its position.
  defp gallery_files_text(%{files: files}) when is_list(files),
    do: Enum.map_join(files, " ", fn f -> join(media_text(f.media)) end)

  defp gallery_files_text(_), do: ""

  # Copyright included so a photographer's name still finds the gallery page — it used to
  # be indexed via the (now dropped) block_gallery_files.copyright column.
  defp media_text(%Bbh.Media.Upload{} = upload),
    do: [upload.caption, upload.title, upload.copyright]

  defp media_text(_), do: []

  # Join a list of text fragments into one space-separated string, dropping
  # nils/blanks. Fragments may themselves be lists (e.g. tags) — flattened first.
  defp join(parts) do
    parts
    |> List.flatten()
    |> Enum.reject(&(&1 in [nil, ""]))
    |> Enum.join(" ")
  end
end
