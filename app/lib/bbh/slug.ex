defmodule Bbh.Slug do
  @moduledoc """
  URL slug derived from a German title.

  Umlauts and ß are transliterated the way German readers expect ("Schützenfest" →
  "schuetzenfest"), not stripped — `String.replace(~r/[^a-z0-9]+/, "-")` alone would turn
  them into word breaks.

  Extracted from `mix bbh.import` so the MCP `create_article` tool derives slugs exactly
  the way the Hugo import did; both call this.
  """

  @transliterations %{"ä" => "ae", "ö" => "oe", "ü" => "ue", "ß" => "ss"}

  @doc """
  Slugifies `text`.

      iex> Bbh.Slug.slugify("Schützenfest 2026 — Königsball!")
      "schuetzenfest-2026-koenigsball"
  """
  def slugify(text) when is_binary(text) do
    text
    |> String.downcase()
    |> String.replace(~r/[äöüß]/u, &Map.fetch!(@transliterations, &1))
    |> String.replace(~r/[^a-z0-9]+/, "-")
    |> String.trim("-")
  end
end
