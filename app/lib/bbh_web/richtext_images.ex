defmodule BbhWeb.RichtextImages do
  @moduledoc """
  Enriches the media-library images in rendered rich text: responsive variants, intrinsic
  dimensions, the lightbox trigger and the caption line.

  The editor stores a bare inline `<img src="/media/<key>" class="bbh-img-md
  bbh-float-right">` inside its paragraph — nothing else, so `Bbh.Html.sanitize/1` and
  its block merge stay simple and every image already in the database benefits. At
  render time each such image becomes

      <span class="bbh-fig bbh-img-md bbh-float-right">
        <button type="button" class="bbh-fig-zoom" data-lightbox-src="…" …>
          <img src="…?w=800" srcset="…" sizes="…" width="…" height="…" alt="…">
        </button>
        <span class="bbh-fig-caption">…</span>
      </span>

  Spans, not a `<figure>`: the image sits inside a `<p>`, and a block element there
  would make the HTML parser close the paragraph around it. The stored classes move to
  the wrapper, which is what `assets/css/app.css` sizes and floats. A `bbh-cap-*` class
  limits the caption line to the Bildunterschrift, the copyright, or nothing; without
  one it shows both. The lightbox always gets both.

  Alt text, caption and copyright come from the media library (ADR 0004), read live
  through `BbhWeb.Format` — the `alt` the picker wrote at insert time is only a
  snapshot of it. An image an author linked keeps its link and gets no lightbox
  button (a button cannot sit inside an anchor). Anything that is not a known
  media-library image — an external URL, an unknown key, a PDF — is left untouched.

  See `docs/adr/0013-richtext-images-enriched-at-render.md`.
  """

  import BbhWeb.Format,
    only: [
      media_url: 1,
      media_url: 2,
      image_alt: 1,
      image_caption: 1,
      image_copyright: 1,
      copyright_label: 1
    ]

  alias Bbh.Media

  # The tokens that matter: images, and the anchors around them. Stored HTML is
  # re-serialized by the sanitizer (double-quoted attributes, balanced `</a>`), so a
  # regex is enough.
  @token_re ~r{<a\b[^>]*>|</a\s*>|<img\b[^>]*>}i
  @attr_re ~r/([a-zA-Z_:][-a-zA-Z0-9_:.]*)="([^"]*)"/
  @src_re ~r{\A/media/(?<key>[^?#]+)(?:\?[^#]*)?\z}

  # Variant widths offered in `srcset`; never above the original, since the media
  # controller upscales on request.
  @widths [480, 800, 1200, 1600]
  @src_width 800
  @lightbox_width 1600

  # Animation (GIF) and vector markup (SVG) do not survive a WebP variant; those are
  # served as the original.
  @unresized_types ~w(image/gif image/svg+xml)

  # Rendered width per size class from the md breakpoint (48rem) up. The widest content
  # column (a Verein page next to its sidebar) is about 54rem; below 48rem every image
  # is full width and nothing floats (see app.css).
  @sizes %{
    "bbh-img-sm" => "(min-width: 48rem) min(25vw, 13.5rem), 100vw",
    "bbh-img-md" => "(min-width: 48rem) min(50vw, 27rem), 100vw",
    "bbh-img-lg" => "(min-width: 48rem) min(75vw, 40.5rem), 100vw"
  }
  @default_sizes "(min-width: 48rem) min(100vw, 54rem), 100vw"

  @doc """
  Rewrite every media-library `<img>` in `html` into the enriched markup described in
  the module doc. Loads all referenced uploads with a single query, and none at all
  when the body holds no media image. Passes non-binaries through.
  """
  def rewrite(html) when is_binary(html) do
    tokens = Regex.split(@token_re, html, include_captures: true)

    case tokens |> Enum.map(&media_key/1) |> Enum.reject(&is_nil/1) do
      [] ->
        html

      keys ->
        uploads = Media.get_uploads_by_storage_keys(keys)

        tokens
        |> Enum.map_reduce(0, &rewrite_token(&1, &2, uploads))
        |> elem(0)
        |> IO.iodata_to_binary()
    end
  end

  def rewrite(other), do: other

  # Anchor depth is threaded through so an image inside a link is recognised. The
  # split also yields the text between tokens, which may itself start with markup
  # (`</p><p>`), hence the anchored matches rather than prefix patterns.
  defp rewrite_token(token, depth, uploads) do
    cond do
      Regex.match?(~r/\A<a\b[^>]*>\z/i, token) ->
        {token, depth + 1}

      Regex.match?(~r{\A</a\s*>\z}i, token) ->
        {token, max(depth - 1, 0)}

      key = media_key(token) ->
        case Map.get(uploads, key) do
          %{} = upload -> {enrich(upload, token, depth > 0), depth}
          nil -> {token, depth}
        end

      true ->
        {token, depth}
    end
  end

  defp enrich(upload, tag, in_link?) do
    if Media.image?(upload), do: figure(upload, classes(tag), in_link?), else: tag
  end

  defp media_key(token) do
    with true <- Regex.match?(~r/\A<img\b[^>]*>\z/i, token),
         %{"src" => src} <- attrs(token),
         %{"key" => key} <- Regex.named_captures(@src_re, src) do
      key
    else
      _ -> nil
    end
  end

  defp attrs(tag), do: @attr_re |> Regex.scan(tag) |> Map.new(fn [_, k, v] -> {k, v} end)

  defp classes(tag) do
    tag |> attrs() |> Map.get("class", "") |> String.split(~r/\s+/, trim: true)
  end

  defp figure(upload, classes, in_link?) do
    alt = image_alt(upload)
    img = img(upload, classes, alt)

    inner =
      if in_link?,
        do: img,
        else: [
          ~s(<button type="button" class="bbh-fig-zoom" aria-label="Bild vergrößern"),
          lightbox_attrs(upload, alt),
          ">",
          img,
          "</button>"
        ]

    [
      ~s(<span class="),
      Enum.join(["bbh-fig" | classes], " "),
      ~s(">),
      inner,
      caption(upload, classes),
      "</span>"
    ]
  end

  defp img(upload, classes, alt) do
    [
      "<img",
      source_attrs(upload, classes),
      attr("width", upload.width),
      attr("height", upload.height),
      attr("alt", alt),
      ~s( loading="lazy" decoding="async">)
    ]
  end

  defp source_attrs(upload, classes) do
    if resized?(upload) do
      widths = widths(upload.width)

      [
        attr("src", media_url(upload, width: min(@src_width, upload.width))),
        attr("srcset", Enum.map_join(widths, ", ", &"#{media_url(upload, width: &1)} #{&1}w")),
        attr("sizes", sizes(classes))
      ]
    else
      attr("src", media_url(upload))
    end
  end

  defp lightbox_attrs(upload, alt) do
    src =
      if resized?(upload),
        do: media_url(upload, width: min(@lightbox_width, upload.width)),
        else: media_url(upload)

    [
      attr("data-lightbox-src", src),
      attr("data-lightbox-alt", alt),
      attr("data-lightbox-caption", image_caption(upload)),
      attr("data-lightbox-copyright", copyright_label(image_copyright(upload))),
      attr("data-lightbox-group", "content")
    ]
  end

  # The editor's "Bildunterschrift" picker (`bbh-cap-*`) picks what the line under the
  # image shows; no class means both. The lightbox always carries both.
  defp caption(upload, classes) do
    show = Enum.find_value(classes, "both", &caption_mode/1)
    caption = if show in ~w(both caption), do: image_caption(upload)
    copyright = if show in ~w(both copyright), do: copyright_label(image_copyright(upload))

    case {caption, copyright} do
      {nil, nil} ->
        []

      {caption, copyright} ->
        [
          ~s(<span class="bbh-fig-caption">),
          span("bbh-fig-text", caption),
          span("bbh-fig-copyright", copyright),
          "</span>"
        ]
    end
  end

  defp span(_class, nil), do: []
  defp span(class, text), do: [~s(<span class="), class, ~s(">), escape(text), "</span>"]

  defp caption_mode("bbh-cap-" <> mode) when mode in ~w(none caption copyright), do: mode
  defp caption_mode(_class), do: nil

  defp resized?(upload),
    do:
      is_integer(upload.width) and upload.width > 0 and
        upload.content_type not in @unresized_types

  # The standard widths below the original, plus the original's own width when it is
  # smaller than the largest step — so a small image still gets an exact-size variant.
  defp widths(width) do
    below = Enum.filter(@widths, &(&1 <= width))
    if width < List.last(@widths) and width not in below, do: below ++ [width], else: below
  end

  # A float without a size class renders at half width (see app.css).
  defp sizes(classes) do
    size = Enum.find(classes, &Map.has_key?(@sizes, &1))

    cond do
      size -> @sizes[size]
      Enum.any?(classes, &String.starts_with?(&1, "bbh-float-")) -> @sizes["bbh-img-md"]
      true -> @default_sizes
    end
  end

  defp attr(_name, nil), do: []
  defp attr(name, value), do: [" ", name, ~s(="), escape(value), ~s(")]

  defp escape(value), do: value |> to_string() |> Plug.HTML.html_escape()
end
