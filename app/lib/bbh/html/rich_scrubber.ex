defmodule Bbh.Html.RichScrubber do
  @moduledoc """
  HTML allow-list for the Quill rich-text editor output.

  Extends `HtmlSanitizeEx.basic_html` (headings, lists, links, bold/italic,
  quotes, code, scheme-less/http(s) images) by additionally permitting a `class`
  attribute on the block/inline elements Quill emits. The class *values* are not
  validated here — `Bbh.Html.sanitize/1` narrows them to a fixed token allow-list
  afterwards (alignment + image size). Authoring is admin-only and `class` carries
  no script vector, so this is a safe, layered approach.

  Everything else `basic_html` does still applies: scripts, event handlers,
  inline `style`, `javascript:`/`data:` URLs are stripped.
  """
  use HtmlSanitizeEx, extend: :basic_html

  # Alignment lives as a class on block elements (Quill's ql-align-*, ql-indent-*).
  allow_tag_with_these_attributes("p", ["class"])
  allow_tag_with_these_attributes("h1", ["class"])
  allow_tag_with_these_attributes("h2", ["class"])
  allow_tag_with_these_attributes("h3", ["class"])
  allow_tag_with_these_attributes("h4", ["class"])
  allow_tag_with_these_attributes("h5", ["class"])
  allow_tag_with_these_attributes("h6", ["class"])
  allow_tag_with_these_attributes("ul", ["class"])
  allow_tag_with_these_attributes("ol", ["class"])
  allow_tag_with_these_attributes("li", ["class"])
  allow_tag_with_these_attributes("blockquote", ["class"])
  allow_tag_with_these_attributes("span", ["class"])
  allow_tag_with_these_attributes("a", ["class"])

  # Image size lives as a class (bbh-img-*); src/width/height/alt/title already
  # come from basic_html.
  allow_tag_with_these_attributes("img", ["class"])
end
