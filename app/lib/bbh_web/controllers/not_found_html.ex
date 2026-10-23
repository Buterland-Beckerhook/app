defmodule BbhWeb.NotFoundHTML do
  @moduledoc """
  The public 404 page, rendered by `BbhWeb.Redirector` in the full site layout.

  `BbhWeb.ErrorHTML` stays the bare fallback for errors the endpoint renders itself
  (crashes, a non-GET with no route): those must not depend on the layout, its
  navigation query or a healthy database.
  """
  use BbhWeb, :html

  embed_templates "not_found_html/*"

  @doc """
  A search query guessed from the missing path's last segment, so the search box
  arrives prefilled with something useful.

      iex> BbhWeb.NotFoundHTML.suggested_query("/aktuell/2019/pokal_und-preisschiessen")
      "pokal und preisschiessen"

      iex> BbhWeb.NotFoundHTML.suggested_query("/termine/2023/index.ics")
      ""
  """
  def suggested_query(path) when is_binary(path) do
    path
    |> Bbh.Redirects.normalize_path()
    |> String.split("/", trim: true)
    |> List.last("")
    |> then(&Regex.replace(~r/\.[a-z0-9]{1,5}$/, &1, ""))
    |> String.split(~r/[\s\-_.+]+/, trim: true)
    |> Enum.reject(&(&1 == "index" or Regex.match?(~r/^\d+$/, &1)))
    |> Enum.join(" ")
    |> String.slice(0, 80)
  end
end
