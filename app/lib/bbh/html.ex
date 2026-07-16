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
end
