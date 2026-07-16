defmodule BbhWeb.Format do
  @moduledoc "German date/number formatting and media URL helpers for templates."

  alias Bbh.Media.Upload
  alias Bbh.Content.{Article, ArticleImage}

  @months ~w(Januar Februar März April Mai Juni Juli August September Oktober November Dezember)

  @doc ~s(German long date, e.g. "14. Juli 2024".)
  def de_date(nil), do: ""

  def de_date(%DateTime{} = dt), do: "#{dt.day}. #{Enum.at(@months, dt.month - 1)} #{dt.year}"

  @doc ~s(German date + time, e.g. "14. Juli 2024, 19:30 Uhr".)
  def de_datetime(nil), do: ""

  def de_datetime(%DateTime{} = dt) do
    "#{de_date(dt)}, #{two(dt.hour)}:#{two(dt.minute)} Uhr"
  end

  @doc "German date/time range for an event, collapsing same-day ranges."
  def de_range(%DateTime{} = start, nil, all_day?), do: day_or_datetime(start, all_day?)

  def de_range(%DateTime{} = start, %DateTime{} = stop, all_day?) do
    same_day? = {start.year, start.month, start.day} == {stop.year, stop.month, stop.day}

    cond do
      all_day? and same_day? -> de_date(start)
      all_day? -> "#{de_date(start)} – #{de_date(stop)}"
      same_day? -> "#{de_datetime(start)} – #{two(stop.hour)}:#{two(stop.minute)} Uhr"
      true -> "#{de_datetime(start)} – #{de_datetime(stop)}"
    end
  end

  defp day_or_datetime(dt, true), do: de_date(dt)
  defp day_or_datetime(dt, _), do: de_datetime(dt)

  defp two(n), do: String.pad_leading(Integer.to_string(n), 2, "0")

  @doc """
  URL for an uploaded file, optionally sized. Real serving + responsive variants are
  implemented in the media pipeline; this is the single place templates build URLs.
  """
  def media_url(upload, opts \\ [])
  def media_url(nil, _opts), do: nil
  def media_url(%Ecto.Association.NotLoaded{}, _opts), do: nil

  def media_url(%Upload{storage_key: key}, opts) do
    query =
      [w: opts[:width], h: opts[:height]]
      |> Enum.reject(fn {_k, v} -> is_nil(v) end)

    case query do
      [] -> "/media/#{key}"
      q -> "/media/#{key}?" <> URI.encode_query(q)
    end
  end

  @doc "The best hero image for an article (flagged one, else first), as an ArticleImage."
  def article_hero(%Article{images: images}) when is_list(images) do
    Enum.find(images, & &1.use_as_article_image) || List.first(images)
  end

  def article_hero(_), do: nil

  @doc "The throne picture for a throne (its article image flagged use_as_throne_picture)."
  def throne_picture(%{article: %{images: images}}) when is_list(images) do
    Enum.find(images, & &1.use_as_throne_picture) || List.first(images)
  end

  def throne_picture(_), do: nil

  @doc "Alt text for an article image (its title, falling back to a generic label)."
  def image_alt(%ArticleImage{title: title}) when is_binary(title) and title != "", do: title
  def image_alt(_), do: "Bild"

  @doc """
  Render a stored rich-text body for output: resolve `{{ role.field }}` placeholders,
  retarget external/media links to open in a new tab, and mark the result safe.

  Links to another host or to a `/media/...` asset get `target="_blank"` (with
  `rel="noopener noreferrer"`); internal page links (relative, or absolute to our
  own host) open in place. `mailto:`/`tel:` links are left untouched.

  The stored HTML is already sanitized on write (`Bbh.Html.sanitize/1`), which
  strips `target`/`rel` — so retargeting must happen here, at render time.
  """
  def render_richtext(nil), do: nil

  # sobelow_skip ["XSS.Raw"]
  # Body is sanitized on write via Bbh.Html.sanitize/1 (see @doc above).
  def render_richtext(body) when is_binary(body) do
    body
    |> Bbh.Placeholders.render()
    |> retarget_links()
    |> Phoenix.HTML.raw()
  end

  defp retarget_links(html), do: Regex.replace(~r/<a\b[^>]*>/i, html, &rewrite_anchor/1)

  defp rewrite_anchor(tag) do
    with [_, href] <- Regex.run(~r/href="([^"]*)"/i, tag),
         true <- new_tab?(href) do
      String.replace_suffix(tag, ">", ~s( target="_blank" rel="noopener noreferrer">))
    else
      _ -> tag
    end
  end

  defp new_tab?(href) do
    uri = URI.parse(href)

    cond do
      uri.scheme in ["mailto", "tel"] -> false
      is_binary(uri.host) and uri.host != BbhWeb.Endpoint.host() -> true
      String.starts_with?(uri.path || "", "/media/") -> true
      true -> false
    end
  end
end
