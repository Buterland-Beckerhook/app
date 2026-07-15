defmodule Bbh.Content do
  @moduledoc "Read/query API for articles, thrones, and block-based pages."
  import Ecto.Query
  alias Bbh.Repo
  alias Bbh.Content.{Article, ArticleImage, Throne, Page, PageBlock, Blocks}

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

  ## Admin — article images

  def list_article_images(article_id) do
    Repo.all(
      from i in ArticleImage,
        where: i.article_id == ^article_id,
        order_by: i.sort,
        preload: :media
    )
  end

  def get_article_image!(id), do: ArticleImage |> Repo.get!(id) |> Repo.preload(:media)

  @doc "Attach a media item to an article (appended)."
  def add_article_image(%Article{} = article, media_id) do
    %ArticleImage{}
    |> ArticleImage.changeset(%{
      "article_id" => article.id,
      "media_id" => media_id,
      "sort" => next_image_sort(article.id)
    })
    |> Repo.insert()
  end

  def update_article_image(%ArticleImage{} = image, attrs),
    do: image |> ArticleImage.changeset(attrs) |> Repo.update()

  @doc """
  Make `image_id` the article's preview (hero) image, clearing the flag on all
  its sibling images so exactly one image is ever the preview.
  """
  def set_article_preview_image(%Article{id: article_id}, image_id) do
    now = DateTime.utc_now(:second)

    # Repo.transact rolls back on an {:error, _} return, so an unknown target
    # leaves the sibling-clear un-committed (no article ends up with zero previews).
    Repo.transact(fn ->
      from(i in ArticleImage, where: i.article_id == ^article_id)
      |> Repo.update_all(set: [use_as_article_image: false, updated_at: now])

      {count, _} =
        from(i in ArticleImage, where: i.id == ^image_id and i.article_id == ^article_id)
        |> Repo.update_all(set: [use_as_article_image: true, updated_at: now])

      if count == 1, do: {:ok, image_id}, else: {:error, :not_found}
    end)
  end

  def delete_article_image(%ArticleImage{} = image), do: Repo.delete(image)

  defp next_image_sort(article_id) do
    (Repo.one(from i in ArticleImage, where: i.article_id == ^article_id, select: max(i.sort)) ||
       -1) +
      1
  end

  ## Admin — thrones (edited in the context of their article)

  def create_throne(attrs), do: %Throne{} |> Throne.changeset(attrs) |> Repo.insert()
  def update_throne(%Throne{} = t, attrs), do: t |> Throne.changeset(attrs) |> Repo.update()
  def delete_throne(%Throne{} = t), do: Repo.delete(t)
  def change_throne(%Throne{} = t, attrs \\ %{}), do: Throne.changeset(t, attrs)

  ## Admin CRUD — pages

  def list_pages, do: Repo.all(from p in Page, order_by: [asc: p.sort_order, asc: p.title])
  def count_pages, do: Repo.aggregate(Page, :count, :id)
  def get_page!(id), do: Repo.get!(Page, id)
  def create_page(attrs), do: %Page{} |> Page.changeset(attrs) |> Repo.insert()
  def update_page(%Page{} = page, attrs), do: page |> Page.changeset(attrs) |> Repo.update()
  def change_page(%Page{} = page, attrs \\ %{}), do: Page.changeset(page, attrs)

  @doc "Delete a page along with its page_blocks and the concrete (polymorphic) block rows."
  def delete_page(%Page{} = page) do
    blocks = load_blocks(page)

    Repo.transaction(fn ->
      Enum.each(blocks, fn {pb, _} -> delete_block!(pb) end)
      Repo.delete!(page)
    end)
  end

  ## Admin — page blocks

  @block_defaults %{
    "richtext" => %{body: "<p></p>"},
    "alert" => %{icon: "info", body: "<p></p>"},
    "media_card" => %{image_position: "right"},
    "image_gallery" => %{layout: "grid", lightbox: true},
    "person_list" => %{display_style: "table", filter_honorary: "all", filter_roles: []}
  }

  @doc "Append a new, empty block of the given type to a page."
  def add_block(%Page{} = page, type) when is_map_key(@block_defaults, type) do
    schema = Blocks.schema_for(type)

    Repo.transaction(fn ->
      block = Repo.insert!(struct(schema, Map.fetch!(@block_defaults, type)))

      Repo.insert!(%PageBlock{
        page_id: page.id,
        position: next_position(page.id),
        block_type: type,
        block_id: block.id
      })
    end)
  end

  @doc "Update the concrete block referenced by a page_block."
  def update_block(%PageBlock{} = pb, attrs) do
    schema = Blocks.schema_for(pb.block_type)
    block = Repo.get!(schema, pb.block_id)
    block |> schema.changeset(attrs) |> Repo.update()
  end

  @doc "Delete a page_block and its concrete block."
  def delete_block(%PageBlock{} = pb) do
    Repo.transaction(fn -> delete_block!(pb) end)
  end

  @doc "Swap a block with its neighbour in the given direction (:up | :down)."
  def move_block(page_id, %PageBlock{} = pb, direction) do
    blocks = Repo.all(from x in PageBlock, where: x.page_id == ^page_id, order_by: x.position)
    idx = Enum.find_index(blocks, &(&1.id == pb.id))
    swap = if direction == :up, do: idx - 1, else: idx + 1

    if (idx && swap >= 0) and swap < length(blocks) do
      other = Enum.at(blocks, swap)

      Repo.transaction(fn ->
        set_position!(pb.id, other.position)
        set_position!(other.id, pb.position)
      end)
    else
      # Already at the top/bottom edge — nothing to do.
      {:ok, :noop}
    end
  end

  defp delete_block!(%PageBlock{} = pb) do
    schema = Blocks.schema_for(pb.block_type)
    if block = Repo.get(schema, pb.block_id), do: Repo.delete!(block)
    Repo.delete!(pb)
  end

  defp next_position(page_id) do
    (Repo.one(from pb in PageBlock, where: pb.page_id == ^page_id, select: max(pb.position)) || -1) +
      1
  end

  defp set_position!(pb_id, position) do
    Repo.update_all(from(x in PageBlock, where: x.id == ^pb_id), set: [position: position])
  end

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
