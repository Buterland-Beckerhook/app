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

  def media_url(%Upload{storage_key: key} = upload, opts) do
    query =
      [w: opts[:width], h: opts[:height]]
      |> Enum.concat(focal_params(upload, opts))
      |> Enum.concat(revision_param(upload))
      |> Enum.reject(fn {_k, v} -> is_nil(v) end)

    case query do
      [] -> "/media/#{key}"
      q -> "/media/#{key}?" <> URI.encode_query(q)
    end
  end

  # A focal point only changes a cover crop (both dimensions requested), so it is
  # only carried on the URL then. Rounded to keep the URL — and the derived
  # variant cache key — stable across insignificant float noise.
  defp focal_params(%Upload{focal_point_x: x, focal_point_y: y}, opts)
       when is_number(x) and is_number(y) do
    if opts[:width] && opts[:height],
      do: [fx: Float.round(x * 1.0, 4), fy: Float.round(y * 1.0, 4)],
      else: []
  end

  defp focal_params(_upload, _opts), do: []

  # Rotating an image rewrites the original in place, so the URL has to change or a
  # browser cache (max-age=604800) would keep the old orientation. Only carried once
  # something actually changed, which keeps every untouched URL — and the variant
  # cache entries derived from it — exactly as before. The server ignores `v`.
  defp revision_param(%Upload{revision: rev}) when is_integer(rev) and rev > 0, do: [v: rev]
  defp revision_param(_upload), do: []

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

  @doc """
  Alt text for an image: the media item's Beschreibung — the field that exists for it
  — falling back to caption, then title, then a generic label.

  Accepts an embedding with a preloaded `:media` (article image, gallery file) or the
  upload itself. Caption/copyright/alt all resolve through this module so a picture
  reads the same wherever it is embedded.
  """
  def image_alt(%Upload{} = upload),
    do: presence(upload.description) || alt_fallback(upload) || "Bild"

  def image_alt(%{media: %Upload{} = upload}), do: image_alt(upload)
  def image_alt(_), do: "Bild"

  @doc """
  What `image_alt/1` would fall back to if the Beschreibung were blank, or `nil` when
  there is nothing to fall back to.

  The media editor shows this as the Beschreibung field's placeholder, so an editor can
  see what a picture will announce before deciding to leave the field empty. It reads
  from here rather than restating the rule, which is how the title case — the *internal*
  library label ending up as public alt text — stays visible instead of surprising.
  """
  def alt_fallback(%Upload{} = upload), do: first_present([upload.caption, upload.title])
  def alt_fallback(%{media: %Upload{} = upload}), do: alt_fallback(upload)
  def alt_fallback(_), do: nil

  @doc """
  The caption (Bildunterschrift) to render for an image, or `nil` for none.

  An article image can suppress it (`show_caption`) without touching the media item —
  the caption itself is only ever edited in the media library.
  """
  def image_caption(%ArticleImage{show_caption: false}), do: nil
  def image_caption(%Upload{caption: caption}), do: presence(caption)
  def image_caption(%{media: %Upload{} = upload}), do: image_caption(upload)
  def image_caption(_), do: nil

  @doc "The copyright line to render for an image, or `nil` for none."
  def image_copyright(%Upload{copyright: copyright}), do: presence(copyright)
  def image_copyright(%{media: %Upload{} = upload}), do: image_copyright(upload)
  def image_copyright(_), do: nil

  @doc ~S"""
  A copyright as it is shown: prefixed with „©" unless the text already labels itself
  („© …", „Foto: …"), so an editor's own wording is never doubled up.

  The label forms require their separator on purpose — a rights holder whose *name* opens
  with one of those words („Bildarchiv Stadt Münster", „Fotoclub Nord") still gets its ©.
  """
  def copyright_label(nil), do: nil

  def copyright_label(text) when is_binary(text) do
    case presence(text) do
      nil -> nil
      trimmed -> if labelled?(trimmed), do: trimmed, else: "© " <> trimmed
    end
  end

  defp labelled?(text),
    do: Regex.match?(~r/^(©|\(c\)|copyright\b|(foto|bild|quelle)\s*:)/iu, text)

  defp presence(value) when is_binary(value) do
    case String.trim(value) do
      "" -> nil
      trimmed -> trimmed
    end
  end

  defp presence(_), do: nil

  defp first_present(values), do: Enum.find_value(values, &presence/1)

  @doc """
  Render a stored rich-text body for output: resolve `{{ role.field }}` placeholders,
  retarget external/media links to open in a new tab, obfuscate e-mail addresses, and
  mark the result safe.

  Links to another host or to a `/media/...` asset get `target="_blank"` (with
  `rel="noopener noreferrer"`); internal page links (relative, or absolute to our
  own host) open in place. `tel:` links are left untouched.

  `mailto:` links and addresses typed into the copy are rewritten by
  `BbhWeb.EmailObfuscation.rewrite/1` — the address may be *stored* in the clear, it
  just never reaches the page that way. This runs last, on the finished HTML, so it
  also covers whatever `{{ role.email }}` resolved to.

  The stored HTML is already sanitized on write (`Bbh.Html.sanitize/1`), which
  strips `target`/`rel` — so retargeting must happen here, at render time.
  """
  def render_richtext(nil), do: nil

  # sobelow_skip ["XSS.Raw"]
  # Body is sanitized on write via Bbh.Html.sanitize/1 (see @doc above).
  def render_richtext(body) when is_binary(body) do
    body
    |> Bbh.Placeholders.render()
    # Order matters: obfuscation rewrites a mailto: anchor's href to /kontakt, which
    # `new_tab?/1` reads as an internal link. Retargeting afterwards would still be
    # correct, but only by accident — keep it ahead, where the schemes are intact.
    |> retarget_links()
    |> BbhWeb.EmailObfuscation.rewrite()
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
