defmodule Bbh.Html do
  @moduledoc """
  Sanitization for user-authored rich text (the Trix editor output).

  Applied on save so the stored HTML is already safe; the render sites keep
  using `Phoenix.HTML.raw/1`. `basic_html` keeps the semantic formatting Trix
  produces — headings, lists, links, bold/italic, quotes, code — while dropping
  scripts, event handlers, styles and other dangerous markup.
  """
  def sanitize(nil), do: nil
  def sanitize(html) when is_binary(html), do: HtmlSanitizeEx.basic_html(html)
  def sanitize(other), do: other
end
