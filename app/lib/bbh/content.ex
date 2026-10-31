defmodule Bbh.Content do
  @moduledoc """
  Articles and the content blocks pages and articles share. Pages, thrones and tags
  have their own modules: `Bbh.Content.Pages`, `Bbh.Content.Thrones`, `Bbh.Content.Tags`.
  """
  import Ecto.Query
  alias Bbh.{Authz, Repo}
  alias Bbh.Content.{Article, ArticleBlock, Page, PageBlock, Blocks, Tags}

  @doc """
  Published, real articles (excludes throne-only entries), newest first, paginated.

  With `include_unpublished: true` (logged-in editor preview) the publish-status and
  future-date filters are dropped, so drafts / scheduled / archived articles are listed
  too; throne-only entries stay excluded.

  With `tag: "…"` only articles carrying that tag are listed (the tag links on the site
  lead to `/suche?tag=…`). Compared case-insensitively — tags are typed by hand.
  """
  def list_published_articles(page \\ 1, per_page \\ 10, opts \\ []) do
    now = Bbh.Time.now()

    base =
      if Keyword.get(opts, :include_unpublished, false) do
        from a in Article, where: a.no_article == false, order_by: [desc: a.date_published]
      else
        from a in Article,
          where: a.status == "published" and a.no_article == false and a.date_published <= ^now,
          order_by: [desc: a.date_published]
      end

    base
    |> filter_tag(Keyword.get(opts, :tag))
    |> paginate(page, per_page, preload: :image)
  end

  defp filter_tag(query, tag) when tag in [nil, ""], do: query

  defp filter_tag(query, tag) do
    where(
      query,
      [a],
      fragment("EXISTS (SELECT 1 FROM unnest(?) t WHERE lower(t) = lower(?))", a.tags, ^tag)
    )
  end

  @doc "The N most recent published articles (for the homepage)."
  def latest_articles(n \\ 3) do
    now = Bbh.Time.now()

    from(a in Article,
      where: a.status == "published" and a.no_article == false and a.date_published <= ^now,
      order_by: [desc: a.date_published],
      limit: ^n,
      preload: :image
    )
    |> Repo.all()
  end

  @doc "A single published article by slug + year, with its image and throne."
  def get_published_article(slug, year) do
    now = Bbh.Time.now()

    Repo.one(
      from a in Article,
        where:
          a.slug == ^slug and a.year == ^year and a.status == "published" and
            a.date_published <= ^now,
        preload: [:image, throne: :image]
    )
  end

  @doc """
  The published article that lists `path` among its `aliases` (old URLs carried over
  from the Hugo front matter), or nil. `path` must be normalized
  (`Bbh.Redirects.normalize_path/1`); the aliases are compared case-insensitively and
  without a trailing slash.
  """
  def get_published_article_by_alias(path) when is_binary(path) do
    now = Bbh.Time.now()

    Repo.one(
      from a in Article,
        where:
          a.status == "published" and a.date_published <= ^now and
            fragment(
              "EXISTS (SELECT 1 FROM unnest(?) AS al WHERE rtrim(lower(al), '/') = ?)",
              a.aliases,
              ^path
            ),
        limit: 1
    )
  end

  @doc """
  A single article by slug + year regardless of publish state, with images and
  throne. For the logged-in editor preview only — never expose this to the public.
  """
  def get_article_by_slug_year(slug, year) do
    Repo.one(
      from a in Article,
        where: a.slug == ^slug and a.year == ^year,
        preload: [:image, throne: :image]
    )
  end

  @doc """
  Published, real articles whose publish date has passed but which have not yet
  had their "Neuer Artikel" push sent. Drives the publish-notifier cron.
  """
  def articles_pending_notification do
    now = Bbh.Time.now()

    Repo.all(
      from a in Article,
        where:
          a.status == "published" and a.no_article == false and a.date_published <= ^now and
            is_nil(a.notified_at)
    )
  end

  @doc "Mark an article as notified so its publish push is not sent again."
  def mark_article_notified(%Article{} = article) do
    article
    |> Ecto.Changeset.change(notified_at: Bbh.Time.now())
    |> Repo.update()
  end

  @doc """
  Resolve an owner's polymorphic blocks into `{block_join, block_struct}` tuples, in order.
  The owner is a `%Page{}` (page_blocks) or an `%Article{}` (article_blocks); both order
  the same shared `block_*` tables.
  """
  def load_blocks(owner), do: owner |> List.wrap() |> load_blocks_for() |> Map.get(owner.id, [])

  @doc """
  `load_blocks/1` for many owners of one kind (all pages or all articles) at once: one
  query for the join rows and one per block type, however many owners. Returns
  `%{owner_id => [{join_row, block}]}`; owners without blocks are absent.
  """
  def load_blocks_for([]), do: %{}

  def load_blocks_for([first | _] = owners) do
    {join, key} = block_join(first)
    ids = Enum.map(owners, & &1.id)

    joins =
      Repo.all(from pb in join, where: field(pb, ^key) in ^ids, order_by: [asc: pb.position])

    # Batch-load each block table by the ids referenced for that type.
    by_type = Enum.group_by(joins, & &1.block_type, & &1.block_id)

    loaded =
      Map.new(by_type, fn {type, ids} ->
        schema = Blocks.schema_for(type)
        query = from b in schema, where: b.id in ^ids
        query = preload_block(query, type)
        {type, Map.new(Repo.all(query), &{&1.id, &1})}
      end)

    joins
    |> Enum.map(fn pb -> {pb, get_in(loaded, [pb.block_type, pb.block_id])} end)
    |> Enum.group_by(fn {pb, _block} -> Map.fetch!(pb, key) end)
  end

  # Blocks attach to either a page (page_blocks) or an article (article_blocks), sharing
  # the block_* tables. Map an owner — or one of its join rows — to its join schema and
  # owner-id column.
  defp block_join(%Page{}), do: {PageBlock, :page_id}
  defp block_join(%Article{}), do: {ArticleBlock, :article_id}

  defp block_join_of(%PageBlock{page_id: id}), do: {PageBlock, :page_id, id}
  defp block_join_of(%ArticleBlock{article_id: id}), do: {ArticleBlock, :article_id, id}

  defp preload_block(query, "media_card"), do: preload(query, [:image])
  defp preload_block(query, "image_gallery"), do: preload(query, files: :media)
  defp preload_block(query, "event"), do: preload(query, [:event])
  defp preload_block(query, _), do: query

  ## Admin CRUD — articles

  def list_articles do
    Repo.all(from a in Article, order_by: [desc: a.date_published])
  end

  def count_articles, do: Repo.aggregate(Article, :count, :id)

  @doc "Articles per status, e.g. `%{\"published\" => 12, \"draft\" => 3}`; empty statuses are absent."
  def count_articles_by_status do
    from(r in Article, group_by: r.status, select: {r.status, count(r.id)})
    |> Repo.all()
    |> Map.new()
  end

  @doc """
  `{year, slug, last_modified}` of every published real article, for the sitemap.
  `last_modified` is `date_modified`, else `date_published`.
  """
  def list_published_article_refs do
    Repo.all(
      from a in Article,
        where: a.status == "published" and a.no_article == false,
        select: {a.year, a.slug, coalesce(a.date_modified, a.date_published)}
    )
  end

  def get_article!(id),
    do: Article |> Repo.get!(id) |> Repo.preload([:image, throne: :image])

  @doc """
  Fetch an article by id, or `nil`.

  The tolerant twin of `get_article!/1`, for ids that arrive from the MCP tools rather
  than from markup the server rendered: a non-UUID is a miss instead of an
  `Ecto.Query.CastError`.
  """
  def get_article(id) do
    case cast_uuid(id) do
      {:ok, uuid} -> Article |> Repo.get(uuid) |> Repo.preload(:image)
      :error -> nil
    end
  end

  @doc """
  Create an article.

  `silent: true` marks it as already notified, so publishing it sends no "Neuer Artikel"
  push — neither now nor from the notifier cron. For backfilled old articles.
  """
  def create_article(attrs, opts \\ []) do
    %Article{}
    |> Article.changeset(attrs)
    |> put_canonical_tags()
    |> put_silent(opts)
    |> Repo.insert()
    |> Bbh.Search.reindex_after()
  end

  @doc "Update an article. Takes `silent: true` like `create_article/2`."
  def update_article(%Article{} = article, attrs, opts \\ []) do
    article
    |> Article.changeset(attrs)
    |> put_canonical_tags()
    |> put_silent(opts)
    |> Repo.update()
    |> Bbh.Search.reindex_after()
  end

  # Set in the same write as the publish, so the cron can never see the article
  # published but unmarked in between.
  defp put_silent(changeset, opts) do
    if Keyword.get(opts, :silent, false) and
         is_nil(Ecto.Changeset.get_field(changeset, :notified_at)),
       do: Ecto.Changeset.put_change(changeset, :notified_at, Bbh.Time.now()),
       else: changeset
  end

  @doc """
  Delete an article together with its content blocks (concrete block rows included).
  Admin-only (`Bbh.Authz.can_delete?/2`): `{:error, :unauthorized}` otherwise.
  """
  def delete_article(scope, %Article{} = article) do
    with :ok <- Authz.authorize_delete(scope, article), do: delete_with_blocks(article)
  end

  @doc false
  # Deletes a page or article with its blocks, in one transaction. Unchecked: shared by
  # delete_article/2 and Bbh.Content.Pages.delete_page/2, which authorize first.
  def delete_with_blocks(owner) do
    blocks = load_blocks(owner)

    Repo.transaction(fn ->
      Enum.each(blocks, fn {pb, _} -> delete_block!(pb) end)
      Repo.delete!(owner)
    end)
    |> Bbh.Search.reindex_after()
  end

  def change_article(%Article{} = article, attrs \\ %{}), do: Article.changeset(article, attrs)

  defp put_canonical_tags(changeset) do
    case Ecto.Changeset.fetch_change(changeset, :tags) do
      {:ok, tags} ->
        known = Tags.tag_names(changeset.data.id)
        Ecto.Changeset.put_change(changeset, :tags, Tags.canonical_tags(tags, known))

      :error ->
        changeset
    end
  end

  @doc "Set (or clear with `nil`) the article's single image (the hero + throne default)."
  def set_article_image(%Article{} = article, media_id) do
    # force_change so "set to media_id" always writes, even if a stale struct already
    # carries that value (cast would skip an unchanged field and leave the DB as-is).
    article
    |> Article.changeset(%{})
    |> Ecto.Changeset.force_change(:image_id, media_id)
    |> Repo.update()
    |> Bbh.Search.reindex_after()
  end

  ## Admin — gallery block files (edited in the context of their page)

  @doc "A gallery's images in display order, with their media preloaded."
  def list_gallery_files(gallery_id) do
    Repo.all(
      from f in Blocks.GalleryFile,
        where: f.gallery_id == ^gallery_id,
        order_by: [asc: f.sort, asc: f.inserted_at],
        preload: :media
    )
  end

  @doc "Append a media item to a gallery block."
  def add_gallery_file(%Blocks.ImageGallery{id: gallery_id}, media_id) do
    %Blocks.GalleryFile{}
    |> Blocks.GalleryFile.changeset(%{
      "gallery_id" => gallery_id,
      "media_id" => media_id,
      "sort" => next_gallery_sort(gallery_id)
    })
    |> Repo.insert()
    |> Bbh.Search.reindex_after()
  end

  def get_gallery_file!(id), do: Repo.get!(Blocks.GalleryFile, id)

  @doc """
  The gallery file `id` if it sits in one of `gallery_ids`, else nil. For events that
  carry a raw file id: the editor of one article must not reach another's gallery.
  """
  def get_gallery_file_in(gallery_ids, id) do
    case cast_uuid(id) do
      {:ok, id} ->
        Repo.one(
          from(f in Blocks.GalleryFile, where: f.id == ^id and f.gallery_id in ^gallery_ids)
        )

      :error ->
        nil
    end
  end

  def delete_gallery_file(%Blocks.GalleryFile{} = file),
    do: file |> Repo.delete() |> Bbh.Search.reindex_after()

  @doc "Move a gallery image one step (:up | :down) or to the edge (:top | :bottom)."
  def move_gallery_file(gallery_id, %Blocks.GalleryFile{} = file, direction) do
    files = list_gallery_files(gallery_id)
    reorder(files, Enum.find_index(files, &(&1.id == file.id)), direction, &set_gallery_sort!/2)
  end

  defp next_gallery_sort(gallery_id) do
    (Repo.one(
       from f in Blocks.GalleryFile, where: f.gallery_id == ^gallery_id, select: max(f.sort)
     ) || -1) + 1
  end

  defp set_gallery_sort!(id, sort) do
    Repo.update_all(from(f in Blocks.GalleryFile, where: f.id == ^id), set: [sort: sort])
  end

  ## Admin — content blocks (pages and articles share the same block_* tables)

  @block_defaults %{
    "richtext" => %{body: "<p></p>"},
    "alert" => %{icon: "info", body: "<p></p>"},
    "media_card" => %{image_position: "right"},
    "image_gallery" => %{
      layout: "grid",
      lightbox: true,
      aspect_ratio: "16:9",
      grid_fit: "square",
      autoplay: false
    },
    "person_list" => %{
      display_style: "table",
      filter_honorary: "all",
      filter_alive: "all",
      filter_roles: [],
      show_address: false,
      only_active: false
    },
    "separator" => %{},
    "event" => %{show_header: true, show_body: false, show_programme: true},
    "trophy_table" => %{title: "Pokalsieger", show_records: true, show_descriptions: false}
  }

  @doc "Append a new, empty block of the given type to an owner (page or article)."
  def add_block(owner, type) when is_map_key(@block_defaults, type) do
    {join, key} = block_join(owner)
    schema = Blocks.schema_for(type)

    Repo.transaction(fn ->
      block = Repo.insert!(struct(schema, Map.fetch!(@block_defaults, type)))

      Repo.insert!(
        struct(join, %{
          key => owner.id,
          :position => next_position(owner),
          :block_type => type,
          :block_id => block.id
        })
      )
    end)
    |> Bbh.Search.reindex_after()
  end

  @doc """
  Fetch an article's block-join row by id, or `nil`.

  Scoped to `article_blocks` on purpose: a `page_blocks` id must not resolve here, or the
  MCP article tools would reach into page content through a guessed id.
  """
  def get_article_block(id) do
    case cast_uuid(id) do
      {:ok, uuid} -> Repo.get(ArticleBlock, uuid)
      :error -> nil
    end
  end

  @doc """
  The concrete block a join row points at, with the same associations `load_blocks/1`
  preloads — the counterpart to that function for a single row.
  """
  def get_block(pb) do
    Blocks.schema_for(pb.block_type)
    |> from()
    |> preload_block(pb.block_type)
    |> Repo.get(pb.block_id)
  end

  defp cast_uuid(id) when is_binary(id), do: Ecto.UUID.cast(id)
  defp cast_uuid(_id), do: :error

  @doc "Update the concrete block referenced by a block-join row."
  def update_block(pb, attrs) do
    schema = Blocks.schema_for(pb.block_type)
    block = Repo.get!(schema, pb.block_id)
    block |> schema.changeset(attrs) |> Repo.update() |> Bbh.Search.reindex_after()
  end

  @doc "Delete a block-join row and its concrete block."
  def delete_block(pb) do
    Repo.transaction(fn -> delete_block!(pb) end) |> Bbh.Search.reindex_after()
  end

  @doc "Move a block one step (:up | :down) or to the edge (:top | :bottom) within its owner."
  def move_block(pb, direction) do
    {join, key, owner_id} = block_join_of(pb)
    blocks = Repo.all(from x in join, where: field(x, ^key) == ^owner_id, order_by: x.position)

    reorder(
      blocks,
      Enum.find_index(blocks, &(&1.id == pb.id)),
      direction,
      &set_position!(join, &1, &2)
    )
  end

  # Both ordering columns here share their write path with media folders — see
  # Bbh.Ordering for why the whole list is renumbered instead of two values swapped,
  # and for the unique-index constraint that follows from it.
  defp reorder(items, idx, direction, write_position),
    do: Bbh.Ordering.move(items, idx, direction, write_position)

  defp delete_block!(pb) do
    schema = Blocks.schema_for(pb.block_type)
    if block = Repo.get(schema, pb.block_id), do: Repo.delete!(block)
    Repo.delete!(pb)
  end

  defp next_position(owner) do
    {join, key} = block_join(owner)

    (Repo.one(from pb in join, where: field(pb, ^key) == ^owner.id, select: max(pb.position)) ||
       -1) + 1
  end

  defp set_position!(join, id, position) do
    Repo.update_all(from(x in join, where: x.id == ^id), set: [position: position])
  end

  @doc false
  # Minimal offset pagination returning a map the templates/Pagination component use.
  # Shared with Bbh.Content.Thrones.
  def paginate(query, page, per_page, opts) do
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
