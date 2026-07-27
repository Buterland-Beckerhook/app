defmodule Bbh.Content do
  @moduledoc "Read/query API for articles, thrones, and block-based pages."
  import Ecto.Query
  alias Bbh.Repo
  alias Bbh.Content.{Article, ArticleBlock, ArticleImage, Throne, Page, PageBlock, Blocks}

  @doc """
  Published, real articles (excludes throne-only entries), newest first, paginated.

  With `include_unpublished: true` (logged-in editor preview) the publish-status and
  future-date filters are dropped, so drafts / scheduled / archived articles are listed
  too; throne-only entries stay excluded.
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

    paginate(base, page, per_page, preload: [:image, images: :media])
  end

  @doc "The N most recent published articles (for the homepage)."
  def latest_articles(n \\ 3) do
    now = Bbh.Time.now()

    from(a in Article,
      where: a.status == "published" and a.no_article == false and a.date_published <= ^now,
      order_by: [desc: a.date_published],
      limit: ^n,
      preload: [:image, images: :media]
    )
    |> Repo.all()
  end

  @doc "A single published article by slug + year, with images and throne."
  def get_published_article(slug, year) do
    now = Bbh.Time.now()

    Repo.one(
      from a in Article,
        where:
          a.slug == ^slug and a.year == ^year and a.status == "published" and
            a.date_published <= ^now,
        preload: [:image, images: :media, throne: :image]
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
        preload: [:image, images: :media, throne: :image]
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

  @doc "The currently reigning throne (latest by begin year), with its article + images."
  def current_throne do
    Repo.one(
      from t in Throne,
        order_by: [desc: t.begin_year],
        limit: 1,
        preload: [:image, article: [:image, images: :media]]
    )
  end

  @doc """
  The currently reigning throne of each type for the homepage throne section, ordered
  König → Kaiser → Stadtkaiser → Jungschützenkönig. Missing types are omitted.

  König and Jungschützenkönig change yearly, so we take the most recent one. A
  Kaiser/Stadtkaiser reigns until the next Kaiserthron/Stadtschützenfest — which the club
  does not hold every year and may postpone — so the current one is the latest with an
  *open* end year; once it has concluded and no successor exists, none is shown.
  """
  def current_thrones do
    [
      current_throne_of_type("koenig"),
      current_open_throne_of_type("kaiser"),
      current_open_throne_of_type("stadtkaiser"),
      current_throne_of_type("jungschuetzenkoenig")
    ]
    |> Enum.reject(&is_nil/1)
  end

  defp current_throne_of_type(type) do
    Repo.one(
      from t in Throne,
        where: t.type == ^type,
        order_by: [desc: t.begin_year],
        limit: 1,
        preload: [:image, article: [:image, images: :media]]
    )
  end

  # Latest still-reigning throne of a type (no end year set yet).
  defp current_open_throne_of_type(type) do
    Repo.one(
      from t in Throne,
        where: t.type == ^type and is_nil(t.end_year),
        order_by: [desc: t.begin_year],
        limit: 1,
        preload: [:image, article: [:image, images: :media]]
    )
  end

  @doc "Thrones of one type, newest first, paginated (the /thron gallery), with article + images."
  def list_thrones(type, page \\ 1, per_page \\ 1) do
    base = from t in Throne, where: t.type == ^type, order_by: [desc: t.begin_year]
    paginate(base, page, per_page, preload: [:image, article: [:image, images: :media]])
  end

  @doc "Schlanke Liste der Throne eines Typs (neueste zuerst) für den /thron-Pager."
  def list_throne_nav(type) do
    Repo.all(
      from t in Throne,
        where: t.type == ^type,
        order_by: [desc: t.begin_year],
        select: %{begin_year: t.begin_year, end_year: t.end_year, king: t.king, type: t.type}
    )
  end

  @doc """
  Data for the Thron dropdown menu: the Kaiser reigns (newest first, with their linked
  article for direct links) and the set of throne types that have at least one record.
  """
  def throne_menu do
    kaiser =
      Repo.all(
        from t in Throne,
          where: t.type == "kaiser",
          order_by: [desc: t.begin_year],
          preload: [:article]
      )

    types = Repo.all(from t in Throne, distinct: true, select: t.type) |> MapSet.new()

    %{kaiser: kaiser, types_present: types}
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

  @doc """
  Resolve an owner's polymorphic blocks into `{block_join, block_struct}` tuples, in order.
  The owner is a `%Page{}` (page_blocks) or an `%Article{}` (article_blocks); both order
  the same shared `block_*` tables.
  """
  def load_blocks(owner) do
    {join, key} = block_join(owner)

    joins =
      Repo.all(from pb in join, where: field(pb, ^key) == ^owner.id, order_by: [asc: pb.position])

    # Batch-load each block table by the ids referenced for that type.
    by_type = Enum.group_by(joins, & &1.block_type, & &1.block_id)

    loaded =
      Map.new(by_type, fn {type, ids} ->
        schema = Blocks.schema_for(type)
        query = from b in schema, where: b.id in ^ids
        query = preload_block(query, type)
        {type, Map.new(Repo.all(query), &{&1.id, &1})}
      end)

    Enum.map(joins, fn pb ->
      {pb, get_in(loaded, [pb.block_type, pb.block_id])}
    end)
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
  defp preload_block(query, _), do: query

  ## Public page navigation (the block-based "Verein" section)

  @doc """
  Published top-level pages (`parent_id` nil) flagged for the menu, ordered by
  `sort_order`. Drives the dynamic "Verein" dropdown and the /verein overview.
  Excludes Impressum/Datenschutz (their `show_in_menu` is false).

  With `include_unpublished` (logged-in editor) draft menu pages are listed too.
  """
  def list_menu_pages(include_unpublished \\ false) do
    from(p in Page,
      where: is_nil(p.parent_id) and p.show_in_menu == true,
      order_by: [asc: p.sort_order, asc: p.title]
    )
    |> maybe_published(include_unpublished)
    |> Repo.all()
  end

  @doc "Published direct children of `parent_id`, ordered by `sort_order`."
  def list_child_pages(parent_id, include_unpublished \\ false) do
    from(p in Page, where: p.parent_id == ^parent_id, order_by: [asc: p.sort_order, asc: p.title])
    |> maybe_published(include_unpublished)
    |> Repo.all()
  end

  # Restricts a page query to published rows, unless previewing (logged-in editor).
  defp maybe_published(query, true), do: query
  defp maybe_published(query, false), do: where(query, [p], p.status == "published")

  @doc """
  Resolve a nested `/verein/*path` (a list of slug segments) to
  `{page, ancestors}` where `ancestors` runs root → leaf (inclusive).

  Returns `nil` unless the whole chain is published, the ancestor slugs match
  the requested segments exactly, and the root is a menu page (`show_in_menu`).
  This rejects wrong nesting (e.g. `/verein/vereinsgeschichte`) and legal pages
  (e.g. `/verein/impressum`).
  """
  def get_page_by_path(segments, include_unpublished \\ false)

  def get_page_by_path([_ | _] = segments, include_unpublished) do
    case find_menu_page(List.last(segments), include_unpublished) do
      {_leaf, ancestors} = result ->
        if Enum.map(ancestors, & &1.slug) == segments, do: result, else: nil

      nil ->
        nil
    end
  end

  def get_page_by_path(_, _), do: nil

  @doc """
  A published page by (globally unique) slug together with its root → leaf
  ancestor chain, but only if the whole chain is published and its root is a
  menu page. Returns `{page, ancestors}` or `nil`.

  Used to build canonical `/verein/...` redirects for non-canonical paths.
  """
  def find_menu_page(slug, include_unpublished \\ false) do
    with %Page{} = leaf <-
           from(p in Page, where: p.slug == ^slug)
           |> maybe_published(include_unpublished)
           |> Repo.one(),
         ancestors = page_ancestors(leaf),
         true <- include_unpublished or Enum.all?(ancestors, &(&1.status == "published")),
         %Page{show_in_menu: true} <- List.first(ancestors) do
      {leaf, ancestors}
    else
      _ -> nil
    end
  end

  @doc "A page's ancestor chain, root → leaf (inclusive)."
  def page_ancestors(%Page{} = page), do: build_ancestors(page, [page])

  defp build_ancestors(%Page{parent_id: nil}, acc), do: acc

  defp build_ancestors(%Page{parent_id: pid}, acc) do
    case Repo.get(Page, pid) do
      nil -> acc
      parent -> build_ancestors(parent, [parent | acc])
    end
  end

  @doc """
  Flat, depth-annotated links for a section's sidebar / mobile select: the root
  page first, then its published descendants in DFS order. Each entry is
  `%{path: canonical_path, title: title, depth: 0-based}`.
  """
  def section_links(%Page{} = root, include_unpublished \\ false),
    do: page_links(root, "/verein/" <> root.slug, 0, include_unpublished)

  @doc """
  Depth-annotated menu tree for the "Verein" dropdown: each published menu page
  (top-level, `show_in_menu`) followed by its published descendants in DFS order.
  Entries are `%{path:, title:, depth:}`; top-level pages keep `depth: 0`. Built
  from a single query.
  """
  def menu_tree(include_unpublished \\ false) do
    by_parent =
      from(p in Page, order_by: [asc: p.sort_order, asc: p.title])
      |> maybe_published(include_unpublished)
      |> Repo.all()
      |> Enum.group_by(& &1.parent_id)

    (by_parent[nil] || [])
    |> Enum.filter(& &1.show_in_menu)
    |> Enum.flat_map(&menu_links(by_parent, &1, "/verein/" <> &1.slug, 0))
  end

  defp menu_links(by_parent, %Page{} = page, path, depth) do
    [
      %{path: path, title: page.title, depth: depth, status: page.status}
      | (by_parent[page.id] || [])
        |> Enum.flat_map(&menu_links(by_parent, &1, path <> "/" <> &1.slug, depth + 1))
    ]
  end

  defp page_links(%Page{} = page, path, depth, include_unpublished) do
    [
      %{path: path, title: page.title, depth: depth, status: page.status}
      | page.id
        |> list_child_pages(include_unpublished)
        |> Enum.flat_map(fn child ->
          page_links(child, path <> "/" <> child.slug, depth + 1, include_unpublished)
        end)
    ]
  end

  @doc "Canonical public path for a page given its root → leaf ancestor chain."
  def page_path(ancestors) when is_list(ancestors),
    do: "/verein/" <> Enum.map_join(ancestors, "/", & &1.slug)

  ## Admin CRUD — articles

  def list_articles do
    Repo.all(from a in Article, order_by: [desc: a.date_published])
  end

  def count_articles, do: Repo.aggregate(Article, :count, :id)

  def get_article!(id),
    do: Article |> Repo.get!(id) |> Repo.preload([:image, images: :media, throne: :image])

  def create_article(attrs),
    do: %Article{} |> Article.changeset(attrs) |> Repo.insert() |> Bbh.Search.reindex_after()

  def update_article(%Article{} = article, attrs),
    do: article |> Article.changeset(attrs) |> Repo.update() |> Bbh.Search.reindex_after()

  @doc "Delete an article together with its content blocks (concrete block rows included)."
  def delete_article(%Article{} = article) do
    blocks = load_blocks(article)

    Repo.transaction(fn ->
      Enum.each(blocks, fn {pb, _} -> delete_block!(pb) end)
      Repo.delete!(article)
    end)
    |> Bbh.Search.reindex_after()
  end

  def change_article(%Article{} = article, attrs \\ %{}), do: Article.changeset(article, attrs)

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

  ## Admin — article images

  def list_article_images(article_id) do
    Repo.all(
      from i in ArticleImage,
        where: i.article_id == ^article_id,
        order_by: [asc: i.sort, asc: i.inserted_at],
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

  def delete_gallery_file(%Blocks.GalleryFile{} = file),
    do: file |> Repo.delete() |> Bbh.Search.reindex_after()

  @doc "Move a gallery image one step in the given direction (:up | :down)."
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

  ## Admin — thrones (edited in the context of their article)

  def create_throne(attrs),
    do: %Throne{} |> Throne.changeset(attrs) |> Repo.insert() |> Bbh.Search.reindex_after()

  def update_throne(%Throne{} = t, attrs),
    do: t |> Throne.changeset(attrs) |> Repo.update() |> Bbh.Search.reindex_after()

  def delete_throne(%Throne{} = t), do: t |> Repo.delete() |> Bbh.Search.reindex_after()
  def change_throne(%Throne{} = t, attrs \\ %{}), do: Throne.changeset(t, attrs)

  @doc "Set (or clear with `nil`) a throne's own picture. `nil` inherits the article image."
  def set_throne_image(%Throne{} = throne, media_id) do
    # force_change so a clear (nil) always writes even when the passed struct is stale —
    # see set_article_image/2.
    throne
    |> Throne.changeset(%{})
    |> Ecto.Changeset.force_change(:image_id, media_id)
    |> Repo.update()
    |> Bbh.Search.reindex_after()
  end

  ## Admin CRUD — pages

  def list_pages, do: Repo.all(from p in Page, order_by: [asc: p.sort_order, asc: p.title])

  @doc """
  All pages in DFS/tree order — each parent immediately followed by its children,
  siblings by `sort_order` then `title` (inherited from `list_pages/0`). Every page
  carries `:depth` (0-based) for indented rendering. Built from a single query.
  """
  def list_pages_tree do
    by_parent = list_pages() |> Enum.group_by(& &1.parent_id)
    flatten_page_tree(by_parent, nil, 0)
  end

  defp flatten_page_tree(by_parent, parent_id, depth) do
    (by_parent[parent_id] || [])
    |> Enum.flat_map(fn p ->
      [%{p | depth: depth} | flatten_page_tree(by_parent, p.id, depth + 1)]
    end)
  end

  def count_pages, do: Repo.aggregate(Page, :count, :id)
  def get_page!(id), do: Repo.get!(Page, id)

  def create_page(attrs),
    do: %Page{} |> Page.changeset(attrs) |> Repo.insert() |> Bbh.Search.reindex_after()

  def update_page(%Page{} = page, attrs),
    do: page |> Page.changeset(attrs) |> Repo.update() |> Bbh.Search.reindex_after()

  def change_page(%Page{} = page, attrs \\ %{}), do: Page.changeset(page, attrs)

  @doc "Delete a page along with its page_blocks and the concrete (polymorphic) block rows."
  def delete_page(%Page{} = page) do
    blocks = load_blocks(page)

    Repo.transaction(fn ->
      Enum.each(blocks, fn {pb, _} -> delete_block!(pb) end)
      Repo.delete!(page)
    end)
    |> Bbh.Search.reindex_after()
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
      autoplay: false
    },
    "person_list" => %{
      display_style: "table",
      filter_honorary: "all",
      filter_roles: [],
      show_address: false,
      only_active: false
    },
    "separator" => %{}
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

  @doc "Move a block one step in the given direction (:up | :down) within its owner."
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
    do: Bbh.Ordering.move_step(items, idx, direction, write_position)

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
