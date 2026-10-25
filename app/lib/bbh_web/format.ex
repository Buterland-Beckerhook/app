defmodule BbhWeb.Format do
  @moduledoc "German date/number formatting and media URL helpers for templates."

  alias Bbh.Media.Upload
  alias Bbh.Content.Article

  @months ~w(Januar Februar März April Mai Juni Juli August September Oktober November Dezember)
  @weekday_abbr ~w(Mo. Di. Mi. Do. Fr. Sa. So.)

  @doc ~s(German long date, e.g. "14. Juli 2024".)
  def de_date(nil), do: ""

  def de_date(%DateTime{} = dt), do: "#{dt.day}. #{Enum.at(@months, dt.month - 1)} #{dt.year}"
  def de_date(%Date{} = d), do: "#{d.day}. #{Enum.at(@months, d.month - 1)} #{d.year}"

  @doc """
  A life date with its place, e.g. "19. Februar 1929 in Gronau". A place that brings its
  own preposition ("im Kirchspiel Epe") is printed as is; no place, just the date.
  """
  def de_life_date(nil, _place), do: ""
  def de_life_date(date, place) when place in [nil, ""], do: de_date(date)

  def de_life_date(date, place) do
    if String.match?(place, ~r/^\p{Ll}/u),
      do: "#{de_date(date)} #{place}",
      else: "#{de_date(date)} in #{place}"
  end

  @doc ~s(German date + time, e.g. "14. Juli 2024, 19:30 Uhr".)
  def de_datetime(nil), do: ""

  def de_datetime(%DateTime{} = dt) do
    "#{de_date(dt)}, #{two(dt.hour)}:#{two(dt.minute)} Uhr"
  end

  @doc ~s(German weekday abbreviation, e.g. "So.".)
  def de_weekday_abbr(%DateTime{} = dt), do: Enum.at(@weekday_abbr, Date.day_of_week(dt) - 1)

  @doc ~s(Compact German date + time with weekday, e.g. "So., 19.07.2026 14:20".)
  def de_short_datetime(%DateTime{} = dt) do
    "#{de_weekday_abbr(dt)}, #{two(dt.day)}.#{two(dt.month)}.#{dt.year} #{two(dt.hour)}:#{two(dt.minute)}"
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

  # Candidate widths for `media_srcset/2`. A fixed ladder, so every template asks for
  # the same handful of variants and the on-disk cache does not fan out per call site.
  @srcset_widths [320, 480, 640, 800, 960, 1280, 1600]

  # Animation (GIF) and vector markup (SVG) do not survive a WebP variant; those are
  # served as the original and get no `srcset`.
  @unresized_types ~w(image/gif image/svg+xml)

  @doc """
  `srcset` for the variant `media_url(upload, opts)` points at: the ladder widths below
  the requested `:width`, plus that width itself, so the browser can pick a smaller
  file on a narrow or low-density screen. With `:height` too (a cover crop) every
  candidate keeps the requested aspect ratio, and with it the focal point.

  Never above the original's own width: the media controller would upscale, and the
  `w` descriptor has to state the width the browser actually gets. `nil` when there
  is nothing to choose from (no width requested, unknown dimensions, GIF/SVG, or a
  single candidate), so `srcset={...}` simply drops the attribute. Pair it with a
  `sizes` that matches the rendered width.
  """
  def media_srcset(upload, opts)

  def media_srcset(%Upload{width: original, content_type: type} = upload, opts)
      when is_integer(original) and original > 0 and type not in @unresized_types do
    case opts[:width] do
      width when is_integer(width) and width > 0 ->
        top = min(width, original)

        case Enum.filter(@srcset_widths, &(&1 < top)) ++ [top] do
          [_only] ->
            nil

          widths ->
            Enum.map_join(widths, ", ", fn w ->
              height = scaled_height(opts[:height], w, width)
              "#{media_url(upload, width: w, height: height)} #{w}w"
            end)
        end

      _ ->
        nil
    end
  end

  def media_srcset(_upload, _opts), do: nil

  defp scaled_height(nil, _w, _width), do: nil
  defp scaled_height(height, w, width), do: max(1, round(height * w / width))

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
  # browser cache (a year for variants, see BbhWeb.MediaController) would keep the old
  # orientation. Only carried once something actually changed, which keeps every
  # untouched URL — and the variant cache entries derived from it — exactly as before.
  # The server does not resolve by `v`; it only compares it with the current revision
  # to decide how long the response may be cached.
  defp revision_param(%Upload{revision: rev}) when is_integer(rev) and rev > 0, do: [v: rev]
  defp revision_param(_upload), do: []

  @doc """
  Editor-facing status label for an article on preview surfaces (list card / detail
  banner), or `nil` when the article is publicly live. `"Entwurf"` for a draft,
  `"Archiviert"` for an archived one, and `"Geplant für <date>"` for a published
  article whose publish date is still in the future.
  """
  def article_status_label(%Article{status: "draft"}), do: "Entwurf"
  def article_status_label(%Article{status: "archived"}), do: "Archiviert"

  def article_status_label(%Article{status: "published", date_published: %DateTime{} = date}) do
    if DateTime.compare(date, Bbh.Time.now()) == :gt, do: "Geplant für #{de_date(date)}"
  end

  def article_status_label(_), do: nil

  @doc "An article's single image (the hero), as an `%Upload{}`, or `nil`."
  def article_hero(%Article{image: %Upload{} = image}), do: image
  def article_hero(_), do: nil

  @doc """
  The picture for a throne, as an `%Upload{}`, or `nil`. Its own image when set,
  otherwise the linked article's image (the default).
  """
  def throne_picture(%{image: %Upload{} = image}), do: image
  def throne_picture(%{article: %{image: %Upload{} = image}}), do: image
  def throne_picture(_), do: nil

  @doc """
  Public path of the article behind a throne, or `nil` when there is nothing to link
  to: a „Nur Thron-Anzeige“ entry (`no_article`), or an article that is not public
  (draft, archived, scheduled) and would only answer with a 404.
  """
  def throne_article_path(%{article: %Article{no_article: false, status: "published"} = a})
      when is_integer(a.year) and is_binary(a.slug) do
    if DateTime.compare(a.date_published, Bbh.Time.now()) != :gt,
      do: "/aktuell/#{a.year}/#{a.slug}"
  end

  def throne_article_path(_), do: nil

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
  The caption (Bildunterschrift) to render for an image, or `nil` for none. It is
  only ever edited in the media library.
  """
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
  retarget external/media links to open in a new tab, enrich media-library images,
  obfuscate e-mail addresses, and mark the result safe.

  Links to another host or to a `/media/...` asset get `target="_blank"` (with
  `rel="noopener noreferrer"`); internal page links (relative, or absolute to our
  own host) open in place. `tel:` links are left untouched.

  Headings (`h2`–`h4`) get an `id` derived from their text, so a section can be
  linked directly („De Kuckuck up den Tune satt" → `#de_kuckuck_up_den_tune_satt`).
  Ids are unique within one body; a repeated heading gets a `_2`, `_3`, … suffix.

  Inline images become responsive, lightbox-enabled figures with their caption from
  the media library — see `BbhWeb.RichtextImages.rewrite/1`. That step runs ahead of
  the obfuscation so an address in a caption is covered too.

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
    |> anchor_headings()
    # Order matters: obfuscation rewrites a mailto: anchor's href to /kontakt, which
    # `new_tab?/1` reads as an internal link. Retargeting afterwards would still be
    # correct, but only by accident — keep it ahead, where the schemes are intact.
    |> retarget_links()
    |> BbhWeb.RichtextImages.rewrite()
    |> BbhWeb.EmailObfuscation.rewrite()
    |> Phoenix.HTML.raw()
  end

  @doc """
  Mark already-sanitized HTML as safe for output without the richtext rewrites.
  Only for values that went through `Bbh.Html.sanitize/1` on write (e.g. the home
  page notice in the site settings).
  """
  def sanitized_html(nil), do: nil

  # sobelow_skip ["XSS.Raw"]
  # Callers pass only HTML sanitized on write via Bbh.Html.sanitize/1 (see @doc).
  def sanitized_html(html) when is_binary(html), do: Phoenix.HTML.raw(html)

  @doc """
  A QR code for `text` as inline SVG, ready to output in a template.
  """
  # sobelow_skip ["XSS.Raw"]
  # The SVG is generated here by EQRCode from the encoded matrix; `text` only decides
  # which modules are dark and never appears in the markup.
  def qr_code(text, width) when is_binary(text) do
    text |> EQRCode.encode() |> EQRCode.svg(width: width) |> Phoenix.HTML.raw()
  end

  @heading_re ~r{<(h[2-4])((?:\s[^>]*)?)>(.*?)</\1\s*>}is

  # Stored HTML is re-serialized by the sanitizer, so a regex is enough here too. The
  # id follows the slug rules, with `_` for the separator: `Bbh.Slug` transliterates
  # umlauts the way German readers expect.
  defp anchor_headings(html) do
    {html, _taken} =
      @heading_re
      |> Regex.split(html, include_captures: true)
      |> Enum.map_reduce(MapSet.new(), &anchor_heading/2)

    IO.iodata_to_binary(html)
  end

  defp anchor_heading(chunk, taken) do
    with [_, tag, attrs, inner] <- Regex.run(@heading_re, chunk),
         false <- attrs =~ ~r/\sid=/i,
         base when base != "" <- heading_id(inner) do
      id = unique_id(base, taken)
      {~s(<#{tag} id="#{id}"#{attrs}>#{inner}</#{tag}>), MapSet.put(taken, id)}
    else
      _ -> {chunk, taken}
    end
  end

  defp heading_id(inner) do
    inner
    |> String.replace(~r/<[^>]*>/, "")
    |> String.replace(~r/&(amp|quot|#39|lt|gt|nbsp);/, " ")
    |> Bbh.Slug.slugify()
    |> String.replace("-", "_")
  end

  defp unique_id(base, taken, n \\ 1) do
    id = if n == 1, do: base, else: "#{base}_#{n}"
    if MapSet.member?(taken, id), do: unique_id(base, taken, n + 1), else: id
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
