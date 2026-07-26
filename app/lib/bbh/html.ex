defmodule Bbh.Html do
  @moduledoc """
  Sanitization for user-authored rich text (the Quill editor output).

  Applied on save so the stored HTML is already safe; the render sites keep
  using `Phoenix.HTML.raw/1`. `Bbh.Html.RichScrubber` keeps the semantic
  formatting Quill produces — headings, lists, links, bold/italic, quotes, code,
  images — while dropping scripts, event handlers, inline styles and other
  dangerous markup.

  It also permits `<img>` and `<a>` whose URL has no scheme or an `http`/`https`
  (or `mailto`) scheme, which is what makes the media-library picker work: images
  and download links point at our own scheme-less `/media/...` paths. `javascript:`
  and `data:` URLs and inline handlers (e.g. `onerror`) are still stripped.

  A `mailto:` link may be *stored* in the clear; it never reaches the page that way.
  `BbhWeb.Format.render_richtext/1` hands the finished HTML to
  `BbhWeb.EmailObfuscation.rewrite/1` — see `docs/adr/0005-email-obfuscation.md`.

  Quill encodes alignment and image size as CSS classes (`ql-align-*`,
  `ql-indent-*`, `bbh-img-*`). The scrubber allows the `class` attribute; this
  module then narrows the values to `@allowed_classes` so no other class can be
  stored, dropping the attribute entirely when nothing survives.

  Finally it rewrites Quill's paragraph model: Quill emits one `<p>` per line, so
  a single break already reads as a full paragraph. On write it collapses
  consecutive paragraphs into one `<p>` joined by `<br />`, keeping a real `<p>`
  only where the author left a blank line. `to_editor/1` reverses this for loading
  content back into the editor; see it for the round-trip details.
  """

  # The only class tokens allowed to survive sanitization. Everything Quill's
  # toolbar can produce (alignment, list indentation, image size) is here; any
  # other class is stripped.
  @allowed_classes ~w(
    ql-align-center ql-align-right ql-align-justify
    ql-indent-1 ql-indent-2 ql-indent-3 ql-indent-4 ql-indent-5
    ql-indent-6 ql-indent-7 ql-indent-8 ql-indent-9
    bbh-img-sm bbh-img-md bbh-img-lg bbh-img-full
    bbh-weight-100 bbh-weight-200 bbh-weight-300 bbh-weight-400 bbh-weight-500
    bbh-weight-600 bbh-weight-700 bbh-weight-800 bbh-weight-900
    bbh-size-xs bbh-size-sm bbh-size-lg bbh-size-xl bbh-size-2xl
    bbh-muted-on
  )

  def sanitize(nil), do: nil

  def sanitize(html) when is_binary(html) do
    html
    |> Bbh.Html.RichScrubber.sanitize()
    |> filter_classes()
    |> merge_paragraphs()
    |> normalize_spaces()
  end

  def sanitize(other), do: other

  @doc """
  Prepare stored HTML for editing in the Quill editor (inverse of the paragraph
  merge that `sanitize/1` applies on write).

  Quill's data model has no soft line break: every `<br>` becomes its own
  paragraph when content is pasted in, and the editor can't tell a former `<br>`
  apart from a real paragraph boundary. Left alone, re-saving would merge *every*
  line into one paragraph. So before loading, insert an empty `<p></p>` between
  each pair of adjacent real paragraphs. Quill keeps those blank lines, and the
  next save collapses only the paragraphs that were joined by `<br>` — the
  round-trip stays stable. Lines that were `<br>`-joined inside one `<p>` come
  back as adjacent paragraphs (no blank between), so the merge rejoins them.
  """
  def to_editor(nil), do: nil

  def to_editor(html) when is_binary(html) do
    with_blocks(html, fn blocks ->
      blocks
      |> Enum.reduce({[], nil}, fn [full, tag, _attrs, _inner], {out, prev} ->
        sep = if prev == "p" and tag == "p", do: "<p></p>", else: ""
        {[full, sep | out], tag}
      end)
      |> then(fn {out, _prev} -> out |> Enum.reverse() |> Enum.join() end)
    end)
  end

  def to_editor(other), do: other

  # Top-level block elements Quill emits. Its output is flat (no block nests
  # inside another), so a non-greedy match per tag with a backreferenced close is
  # enough to tokenize the whole body in order.
  @block_re ~r{<(p|h[1-6]|ul|ol|blockquote|pre)\b([^>]*)>(.*?)</\1>}s

  # Collapse runs of consecutive paragraphs into a single `<p>` whose lines are
  # joined by `<br />`, treating an empty paragraph as a hard paragraph break.
  # This is what turns the editor's "one `<p>` per line" output into the intended
  # "single break -> `<br>`, blank line -> new `<p>`". Paragraphs with different
  # attributes (e.g. a differing alignment class) are never merged, so per-line
  # alignment survives. `to_editor/1` is the inverse.
  defp merge_paragraphs(html) do
    with_blocks(html, fn blocks ->
      {out, run} =
        Enum.reduce(blocks, {[], nil}, fn [full, tag, attrs, inner], {out, run} ->
          cond do
            tag != "p" -> {[full, flush_run(run) | out], nil}
            empty_paragraph?(inner) -> {[flush_run(run) | out], nil}
            run == nil -> {out, {attrs, [inner]}}
            match?({^attrs, _}, run) -> {out, {attrs, [inner | elem(run, 1)]}}
            true -> {[flush_run(run) | out], {attrs, [inner]}}
          end
        end)

      [flush_run(run) | out] |> Enum.reverse() |> Enum.join()
    end)
  end

  defp flush_run(nil), do: ""

  defp flush_run({attrs, lines}) do
    "<p#{attrs}>" <> (lines |> Enum.reverse() |> Enum.join("<br />")) <> "</p>"
  end

  # A paragraph carrying no text — only (self-closing or not) `<br>` and
  # whitespace. Quill emits these for blank lines; they mark paragraph breaks.
  defp empty_paragraph?(inner) do
    inner |> String.replace(~r{<br\s*/?>}i, "") |> String.trim() == ""
  end

  # Tokenize `html` into ordered top-level blocks and hand them to `fun`. If the
  # tokens don't account for the whole input (unexpected markup, nested blocks),
  # return `html` untouched rather than risk mangling it — the block transforms
  # are best-effort formatting, never a correctness guarantee.
  defp with_blocks(html, fun) do
    blocks = Regex.scan(@block_re, html)
    rebuilt = blocks |> Enum.map_join("", &hd/1)

    if compact(rebuilt) == compact(html) do
      fun.(blocks)
    else
      html
    end
  end

  # Drop whitespace that sits purely between tags so the coverage check ignores
  # inter-block indentation/newlines (text inside a block is left alone).
  defp compact(html), do: html |> String.replace(~r/>\s+</s, "><") |> String.trim()

  # Quill's getSemanticHTML() escapes every space as `&nbsp;` (the scrubber may
  # leave it as the U+00A0 char). That breaks `{{ placeholder }}` resolution and
  # wrapping, so restore normal spaces. Belt-and-suspenders with the client-side
  # revert — this also cleans any pre-existing content on its next save.
  defp normalize_spaces(html) do
    html
    |> String.replace(" ", " ")
    |> String.replace("&nbsp;", " ")
  end

  # Keep only whitelisted class tokens; drop the attribute when none remain.
  # Runs after the scrubber, so it only ever sees `class` on already-allowed tags.
  defp filter_classes(html) do
    Regex.replace(~r/\sclass="([^"]*)"/i, html, fn _full, classes ->
      case classes
           |> String.split(~r/\s+/, trim: true)
           |> Enum.filter(&(&1 in @allowed_classes)) do
        [] -> ""
        kept -> ~s( class="#{Enum.join(kept, " ")}")
      end
    end)
  end

  @doc """
  Strip all markup from stored HTML, yielding plain text for the search index.

  Drops every tag (via `HtmlSanitizeEx.strip_tags/1`), decodes entities, and
  collapses whitespace so block/inline boundaries don't glue words together.
  """
  def to_text(nil), do: ""

  def to_text(html) when is_binary(html) do
    html
    # Turn tag boundaries into spaces so "<p>a</p><p>b</p>" doesn't become "ab".
    |> String.replace(~r/<[^>]+>/, " ")
    |> HtmlSanitizeEx.strip_tags()
    |> decode_entities()
    |> String.replace(~r/\s+/u, " ")
    |> String.trim()
  end

  # The handful of HTML entities the editor emits; decoded so they don't survive as
  # noise tokens ("amp", "nbsp") in the search index.
  @entities %{
    "&amp;" => "&",
    "&lt;" => "<",
    "&gt;" => ">",
    "&quot;" => "\"",
    "&#39;" => "'",
    "&apos;" => "'",
    "&nbsp;" => " "
  }

  defp decode_entities(text) do
    Enum.reduce(@entities, text, fn {entity, char}, acc ->
      String.replace(acc, entity, char)
    end)
  end
end
