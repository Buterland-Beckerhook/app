defmodule Bbh.Content do
  @moduledoc "Read/query API for articles, thrones, and block-based pages."
  import Ecto.Query
  alias Bbh.Repo
  alias Bbh.Content.{Article, Throne, Page, PageBlock, Blocks}

  @doc "Published, real articles (excludes throne-only entries), newest first, paginated."
  def list_published_articles(page \\ 1, per_page \\ 10) do
    base =
      from a in Article,
        where: a.status == "published" and a.no_article == false,
        order_by: [desc: a.date_published]

    paginate(base, page, per_page, preload: [images: :media])
  end

  @doc "The N most recent published articles (for the homepage)."
  def latest_articles(n \\ 3) do
    from(a in Article,
      where: a.status == "published" and a.no_article == false,
      order_by: [desc: a.date_published],
      limit: ^n,
      preload: [images: :media]
    )
    |> Repo.all()
  end

  @doc "A single published article by slug + year, with images and throne."
  def get_published_article(slug, year) do
    Repo.one(
      from a in Article,
        where: a.slug == ^slug and a.year == ^year and a.status == "published",
        preload: [:throne, images: :media]
    )
  end

  @doc "The currently reigning throne (latest by begin year), with its article + images."
  def current_throne do
    Repo.one(
      from t in Throne,
        order_by: [desc: t.begin_year],
        limit: 1,
        preload: [article: [images: :media]]
    )
  end

  @doc "All thrones newest first, paginated (the /thron gallery), with article + images."
  def list_thrones(page \\ 1, per_page \\ 1) do
    base = from t in Throne, order_by: [desc: t.begin_year]
    paginate(base, page, per_page, preload: [article: :images])
  end

  @doc """
  A published page by slug together with its ordered, resolved content blocks:
  a list of `{page_block, block_struct}` tuples.
  """
  def get_published_page(slug) do
    case Repo.one(from p in Page, where: p.slug == ^slug and p.status == "published") do
      nil -> nil
      page -> {page, load_blocks(page)}
    end
  end

  @doc "Resolve a page's polymorphic blocks into `{page_block, block_struct}` tuples, in order."
  def load_blocks(%Page{} = page) do
    page_blocks =
      Repo.all(from pb in PageBlock, where: pb.page_id == ^page.id, order_by: [asc: pb.position])

    # Batch-load each block table by the ids referenced for that type.
    by_type = Enum.group_by(page_blocks, & &1.block_type, & &1.block_id)

    loaded =
      Map.new(by_type, fn {type, ids} ->
        schema = Blocks.schema_for(type)
        query = from b in schema, where: b.id in ^ids
        query = preload_block(query, type)
        {type, Map.new(Repo.all(query), &{&1.id, &1})}
      end)

    Enum.map(page_blocks, fn pb ->
      {pb, get_in(loaded, [pb.block_type, pb.block_id])}
    end)
  end

  defp preload_block(query, "media_card"), do: preload(query, [:image])
  defp preload_block(query, "image_gallery"), do: preload(query, files: :media)
  defp preload_block(query, _), do: query

  ## Admin CRUD — articles

  def list_articles do
    Repo.all(from a in Article, order_by: [desc: a.date_published])
  end

  def count_articles, do: Repo.aggregate(Article, :count, :id)

  def get_article!(id), do: Article |> Repo.get!(id) |> Repo.preload([:throne, images: :media])

  def create_article(attrs), do: %Article{} |> Article.changeset(attrs) |> Repo.insert()

  def update_article(%Article{} = article, attrs),
    do: article |> Article.changeset(attrs) |> Repo.update()

  def delete_article(%Article{} = article), do: Repo.delete(article)

  def change_article(%Article{} = article, attrs \\ %{}), do: Article.changeset(article, attrs)

  # Minimal offset pagination returning a map the templates/Pagination component use.
  defp paginate(query, page, per_page, opts) do
    page = max(page, 1)
    total = Repo.aggregate(query, :count, :id)

    entries =
      query
      |> limit(^per_page)
      |> offset(^((page - 1) * per_page))
      |> preload(^Keyword.get(opts, :preload, []))
      |> Repo.all()

    %{
      entries: entries,
      page: page,
      per_page: per_page,
      total: total,
      total_pages: max(ceil(total / per_page), 1)
    }
  end
end
