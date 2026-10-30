defmodule Bbh.Content.Tags do
  @moduledoc """
  Article tags. They stay a plain string list on the article; the tag list is derived
  from the articles, so a tag no article carries any more simply disappears.
  """
  import Ecto.Query
  alias Bbh.{Authz, Repo}
  alias Bbh.Content.Article

  #
  # Tags stay a plain string list on the article; the tag list is derived from the
  # articles, so a tag no article carries any more simply disappears.

  @doc "Every tag in use (drafts included) with the number of its articles, A–Z."
  def list_tags do
    from(a in Article,
      inner_lateral_join: t in fragment("SELECT unnest(?) AS name", a.tags),
      on: true,
      group_by: t.name,
      select: %{name: t.name, count: count(a.id)},
      order_by: [asc: fragment("lower(?)", t.name), asc: t.name]
    )
    |> Repo.all()
  end

  @doc """
  The tags to suggest while typing, A–Z. `except` (an article id) leaves out tags only
  that article carries — otherwise fixing a tag's spelling on its only article would
  snap straight back to the old one.
  """
  def tag_names(except \\ nil) do
    from(a in Article,
      inner_lateral_join: t in fragment("SELECT unnest(?) AS name", a.tags),
      on: true,
      group_by: t.name,
      select: t.name,
      order_by: [desc: count(a.id), asc: t.name]
    )
    |> exclude_article(except)
    |> Repo.all()
    # Most used first above, so the common spelling wins among case variants.
    |> Enum.uniq_by(&String.downcase/1)
    |> Enum.sort_by(&String.downcase/1)
  end

  defp exclude_article(query, nil), do: query
  defp exclude_article(query, id), do: where(query, [a], a.id != ^id)

  @doc """
  Spell each tag the way it is already in use (`"thron"` → `"Thron"`), so the same tag
  doesn't split into case variants. `known` is a list from `tag_names/1`.
  """
  def canonical_tags(tags, known) do
    index = Map.new(known, &{String.downcase(&1), &1})
    Enum.map(tags, &Map.get(index, String.downcase(&1), &1))
  end

  @doc """
  Rename a tag on every article carrying it (exact spelling). Renaming onto a tag that
  already exists merges the two. Returns `{:ok, count}` of the articles changed.

  Not an edit of the articles' content, so „Geändert am“ stays as it is.
  """
  def rename_tag(old, new) when is_binary(old) and is_binary(new) do
    case Article.normalize_tags([new]) do
      [new] ->
        new = canonical_tags([new], List.delete(tag_names(), old)) |> hd()
        retag(old, fn tags -> Enum.map(tags, &if(&1 == old, do: new, else: &1)) end)

      _ ->
        {:error, "Bitte genau ein Schlagwort angeben (ohne Komma)."}
    end
  end

  @doc """
  Remove a tag (exact spelling) from every article. Returns `{:ok, count}`; admin-only,
  `{:error, :unauthorized}` otherwise.
  """
  def delete_tag(scope, tag) when is_binary(tag) do
    with :ok <- Authz.authorize_delete(scope, :tag), do: retag(tag, &List.delete(&1, tag))
  end

  defp retag(tag, fun) do
    Repo.transaction(fn ->
      articles = Repo.all(from a in Article, where: ^tag in a.tags)

      for a <- articles do
        a |> Ecto.Changeset.change(tags: Article.normalize_tags(fun.(a.tags))) |> Repo.update!()
      end

      length(articles)
    end)
    |> Bbh.Search.reindex_after()
  end
end
