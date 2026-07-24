defmodule Bbh.Html do
  @moduledoc """
  Sanitization for user-authored rich text (the Trix editor output).

  Applied on save so the stored HTML is already safe; the render sites keep
  using `Phoenix.HTML.raw/1`. `basic_html` keeps the semantic formatting Trix
  produces — headings, lists, links, bold/italic, quotes, code — while dropping
  scripts, event handlers, styles and other dangerous markup.

  It also permits `<img>` and `<a>` whose URL has no scheme or an `http`/`https`
  (or `mailto`) scheme, which is what makes the media-library picker work: images
  and download links point at our own scheme-less `/media/...` paths. `javascript:`
  and `data:` URLs and inline handlers (e.g. `onerror`) are still stripped.
  """
  def sanitize(nil), do: nil
  def sanitize(html) when is_binary(html), do: HtmlSanitizeEx.basic_html(html)
  def sanitize(other), do: other

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

  # The handful of HTML entities Trix emits; decoded so they don't survive as
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
