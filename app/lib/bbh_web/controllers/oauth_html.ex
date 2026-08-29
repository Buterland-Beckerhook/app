defmodule BbhWeb.OAuthHTML do
  @moduledoc """
  The consent screen and its refusal page, rendered by `BbhWeb.OAuthController`.

  Both are ordinary server-rendered pages rather than LiveViews: a consent form posts once
  and navigates away, so a socket would buy nothing and add a second thing to keep
  authenticated.
  """
  use BbhWeb, :html

  embed_templates "oauth_html/*"

  @doc """
  What a scope means, in the words of the person granting it.

  Deliberately not the scope string: "mcp:write" tells a developer what is being asked and
  tells nobody else, and a consent screen no one can read is consent in name only.
  """
  def scope_label("mcp:read"), do: "Artikel und Medien lesen"
  def scope_label("mcp:write"), do: "Artikel schreiben und bearbeiten"
  def scope_label(scope), do: scope
end
