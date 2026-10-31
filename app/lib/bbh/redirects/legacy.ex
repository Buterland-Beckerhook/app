defmodule Bbh.Redirects.Legacy do
  @moduledoc """
  Maps URLs of the old Hugo site onto current content, by rule rather than by a
  stored table, so the mapping follows the content (a renamed slug or a deleted
  article simply stops redirecting).

  Hugo built URLs from file and directory names, the one-time import
  derived slugs with `Bbh.Slug.slugify/1`. Most URLs therefore survived unchanged and
  never reach this module; what does:

    * names with `_` or `ß` — `/aktuell/2020/kein_biwak` → `/aktuell/2020/kein-biwak`
    * `aliases:` from the Hugo front matter (kept on `articles.aliases`)
    * per-event calendar files — `/termine/2023/biwak/index.ics` → `…/event.ics`
    * section, pagination, taxonomy and feed URLs Hugo generated on its own
    * `/datenschutzerklaerung` → `/datenschutz`

  Only targets that actually resolve are returned; everything else stays a 404 (and
  shows up in the 404 log). Input must be a normalized path
  (`Bbh.Redirects.normalize_path/1`).
  """

  alias Bbh.{Calendar, Content, Slug}

  @doc "The current path for an old Hugo `path`, or nil."
  def resolve(path) when is_binary(path) do
    alias_target(path) || structural(String.split(path, "/", trim: true), path)
  end

  defp alias_target(path) do
    case Content.get_published_article_by_alias(path) do
      nil -> nil
      article -> article_path(article)
    end
  end

  defp structural(["datenschutzerklaerung"], _path), do: "/datenschutz"

  # Site-wide and section RSS feeds; there is no feed any more, the listing is closest.
  defp structural(["index.xml"], _path), do: "/aktuell"
  defp structural(["aktuell", "index.xml"], _path), do: "/aktuell"

  # Hugo's default taxonomies. A tag page becomes a search for the tag.
  defp structural([taxonomy], _path) when taxonomy in ["tags", "categories"], do: "/aktuell"

  defp structural(["tags", tag], _path),
    do: "/suche?" <> URI.encode_query(%{"q" => String.replace(tag, "-", " ")})

  defp structural(["aktuell", "page", page], _path) do
    case Integer.parse(page) do
      {n, ""} when n > 1 -> "/aktuell?seite=#{n}"
      _ -> "/aktuell"
    end
  end

  # Year sections.
  defp structural(["aktuell", year], _path), do: if(year?(year), do: "/aktuell")
  defp structural(["termine", year], _path), do: if(year?(year), do: "/termine?jahr=#{year}")

  # Year and site calendars collapse into the one subscription feed.
  defp structural(["termine", year, "index.ics"], _path),
    do: if(year?(year), do: "/termine/abo.ics")

  defp structural(["aktuell", year, name], path) do
    with y when is_integer(y) <- parse_year(year),
         slug = Slug.slugify(name),
         article when not is_nil(article) <- Content.get_published_article(slug, y) do
      unless_same(article_path(article), path)
    else
      _ -> nil
    end
  end

  defp structural(["termine", year, name], path) do
    with event when not is_nil(event) <- event(year, name) do
      unless_same(event_path(event), path)
    end
  end

  defp structural(["termine", year, name, "index.ics"], _path) do
    with event when not is_nil(event) <- event(year, name) do
      event_path(event) <> "/event.ics"
    end
  end

  defp structural(_segments, _path), do: nil

  defp event(year, name) do
    case parse_year(year) do
      nil -> nil
      y -> Calendar.get_public_event(Slug.slugify(name), y)
    end
  end

  defp article_path(article), do: "/aktuell/#{article.year}/#{article.slug}"
  defp event_path(event), do: Bbh.Calendar.Paths.path(event)

  # Never answer a path with itself (it 404s for some other reason, e.g. unpublished).
  defp unless_same(target, path), do: if(target != path, do: target)

  defp year?(value), do: not is_nil(parse_year(value))

  defp parse_year(value) do
    case Integer.parse(value) do
      {y, ""} when y >= 1900 and y <= 2100 -> y
      _ -> nil
    end
  end
end
