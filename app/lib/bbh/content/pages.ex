defmodule Bbh.Content.Pages do
  @moduledoc """
  The block-based pages: the public /verein tree (menu, sections, ancestors, paths),
  unlisted and system pages, and their admin CRUD. Blocks themselves are handled by
  `Bbh.Content` (shared with articles).
  """
  import Ecto.Query
  alias Bbh.{Authz, Content, Repo}
  alias Bbh.Content.Page

  @doc """
  A published page by slug together with its ordered, resolved content blocks:
  a list of `{page_block, block_struct}` tuples.
  """
  def get_published_page(slug) do
    case Repo.one(from p in Page, where: p.slug == ^slug and p.status == "published") do
      nil -> nil
      page -> {page, Content.load_blocks(page)}
    end
  end

  @doc """
  Published top-level pages (`parent_id` nil) flagged for the menu, ordered by
  `sort_order`. Drives the dynamic "Verein" dropdown and the /verein overview.
  Only `placement: "menu"` pages; unlisted and system pages never appear here.

  With `include_unpublished` (logged-in editor) draft menu pages are listed too.
  """
  def list_menu_pages(include_unpublished \\ false) do
    from(p in Page,
      where: is_nil(p.parent_id) and p.placement == "menu",
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
  the requested segments exactly, and the root is a menu page (`placement: "menu"`).
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
         %Page{placement: "menu"} <- List.first(ancestors) do
      {leaf, ancestors}
    else
      _ -> nil
    end
  end

  @doc "A page's ancestor chain, root → leaf (inclusive). One query, however deep."
  def page_ancestors(%Page{parent_id: nil} = page), do: [page]

  def page_ancestors(%Page{parent_id: pid} = page) do
    initial = from(p in Page, where: p.id == ^pid)
    parents = from(p in Page, join: a in "page_ancestors", on: p.id == a.parent_id)

    by_id =
      {"page_ancestors", Page}
      |> recursive_ctes(true)
      |> with_cte("page_ancestors", as: ^union_all(initial, ^parents))
      |> Repo.all()
      |> Map.new(&{&1.id, &1})

    build_ancestors(page, by_id, [page])
  end

  defp build_ancestors(%Page{parent_id: nil}, _by_id, acc), do: acc

  defp build_ancestors(%Page{parent_id: pid}, by_id, acc) do
    case by_id[pid] do
      nil -> acc
      parent -> build_ancestors(parent, by_id, [parent | acc])
    end
  end

  @doc """
  Flat, depth-annotated links for a section's sidebar / mobile select: the root
  page first, then its published descendants in DFS order. Each entry is
  `%{path: canonical_path, title: title, depth: 0-based}`.
  """
  def section_links(%Page{id: root_id}, include_unpublished \\ false) do
    include_unpublished
    |> menu_page_tree()
    |> Enum.drop_while(fn {page, _path, _depth} -> page.id != root_id end)
    |> Enum.with_index()
    |> Enum.take_while(fn {{_page, _path, depth}, i} -> i == 0 or depth > 0 end)
    |> Enum.map(fn {entry, _i} -> menu_link(entry) end)
  end

  @doc """
  Depth-annotated menu tree for the "Verein" dropdown: each published menu page
  (top-level, `placement: "menu"`) followed by its published descendants in DFS order.
  Entries are `%{path:, title:, depth:}`; top-level pages keep `depth: 0`. Built
  from a single query.
  """
  def menu_tree(include_unpublished \\ false),
    do: include_unpublished |> menu_page_tree() |> Enum.map(&menu_link/1)

  defp menu_link({page, path, depth}),
    do: %{path: path, title: page.title, depth: depth, status: page.status}

  @doc """
  Every page reachable under `/verein` as `{page, path, depth}`, in menu order: each menu
  page (top-level, `placement: "menu"`) followed by its descendants depth-first. Without
  `include_unpublished` only pages whose whole chain is published — a draft hides its
  branch. Built from a single query; the menu, section sidebars, sitemap and search
  index all walk this instead of querying per page.
  """
  def menu_page_tree(include_unpublished \\ false) do
    by_parent =
      from(p in Page, order_by: [asc: p.sort_order, asc: p.title])
      |> maybe_published(include_unpublished)
      |> Repo.all()
      |> Enum.group_by(& &1.parent_id)

    (by_parent[nil] || [])
    |> Enum.filter(&(&1.placement == "menu"))
    |> Enum.flat_map(&tree_entries(by_parent, &1, "/verein/" <> &1.slug, 0))
  end

  defp tree_entries(by_parent, %Page{} = page, path, depth) do
    [
      {page, path, depth}
      | (by_parent[page.id] || [])
        |> Enum.flat_map(&tree_entries(by_parent, &1, path <> "/" <> &1.slug, depth + 1))
    ]
  end

  @doc "Canonical public path for a page given its root → leaf ancestor chain."
  def page_path(ancestors) when is_list(ancestors),
    do: "/verein/" <> Enum.map_join(ancestors, "/", & &1.slug)

  @doc """
  An unlisted page (top-level, `placement: "unlisted"`) by slug, served under
  `/seite/:slug`. Returns `{page, blocks}` or `nil`.

  With `include_unpublished` (logged-in editor) drafts resolve too.
  """
  def get_unlisted_page(slug, include_unpublished \\ false) do
    Page
    |> where([p], p.slug == ^slug and p.placement == "unlisted" and is_nil(p.parent_id))
    |> maybe_published(include_unpublished)
    |> Repo.one()
    |> case do
      nil -> nil
      page -> {page, Content.load_blocks(page)}
    end
  end

  @doc "Published unlisted pages, for the sitemap and search index."
  def list_unlisted_pages do
    Repo.all(
      from p in Page,
        where: p.placement == "unlisted" and is_nil(p.parent_id) and p.status == "published",
        order_by: [asc: p.slug]
    )
  end

  @doc """
  The public URL path of a page, or `nil` when it has none of its own: system
  pages other than Impressum/Datenschutz are only embedded by the application.
  Ignores publication status — used to show editors where a page will live.
  """
  def public_path(%Page{} = page) do
    ancestors = page_ancestors(page)

    case List.first(ancestors) do
      %Page{placement: "menu"} -> page_path(ancestors)
      %Page{placement: "unlisted", slug: slug} -> "/seite/" <> slug
      %Page{placement: "system", slug: slug} when slug in ~w(impressum datenschutz) -> "/" <> slug
      _ -> nil
    end
  end

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

  @doc "Pages per status; empty statuses are absent."
  def count_pages_by_status, do: count_by_status(Page)

  defp count_by_status(queryable) do
    from(r in queryable, group_by: r.status, select: {r.status, count(r.id)})
    |> Repo.all()
    |> Map.new()
  end

  @doc "Which of the given legal-page slugs are published and indexable (not `noindex`)."
  def indexable_page_slugs(slugs) do
    Repo.all(
      from p in Page,
        where: p.slug in ^slugs and p.status == "published" and p.noindex == false,
        select: p.slug
    )
  end

  def get_page!(id), do: Repo.get!(Page, id)
  def get_page(id), do: Repo.get(Page, id)

  def create_page(attrs),
    do: %Page{} |> change_page(attrs) |> Repo.insert() |> Bbh.Search.reindex_after()

  def update_page(%Page{} = page, attrs),
    do: page |> change_page(attrs) |> Repo.update() |> Bbh.Search.reindex_after()

  def change_page(%Page{} = page, attrs \\ %{}),
    do: page |> Page.changeset(attrs) |> validate_page_tree()

  # Only the menu tree nests: a page may hang below a menu-rooted page, and an
  # unlisted/system page — or one that would become one — may not have children.
  defp validate_page_tree(changeset) do
    changeset
    |> validate_parent_in_menu_tree()
    |> validate_no_children_unless_menu()
  end

  defp validate_parent_in_menu_tree(changeset) do
    with parent_id when is_binary(parent_id) <- Ecto.Changeset.get_field(changeset, :parent_id),
         %Page{} = parent <- Repo.get(Page, parent_id),
         %Page{placement: placement} when placement != "menu" <-
           List.first(page_ancestors(parent)) do
      Ecto.Changeset.add_error(
        changeset,
        :parent_id,
        "Unterseiten sind nur unterhalb von Menüseiten möglich."
      )
    else
      _ -> changeset
    end
  end

  defp validate_no_children_unless_menu(changeset) do
    id = changeset.data.id

    if id && Ecto.Changeset.get_field(changeset, :placement) != "menu" &&
         Repo.exists?(from p in Page, where: p.parent_id == ^id) do
      Ecto.Changeset.add_error(
        changeset,
        :placement,
        "Diese Seite hat Unterseiten und muss deshalb im Menü bleiben."
      )
    else
      changeset
    end
  end

  @doc """
  Delete a page along with its page_blocks and the concrete (polymorphic) block rows.
  Admin-only: `{:error, :unauthorized}` otherwise.
  """
  def delete_page(scope, %Page{} = page) do
    with :ok <- Authz.authorize_delete(scope, page), do: Content.delete_with_blocks(page)
  end
end
