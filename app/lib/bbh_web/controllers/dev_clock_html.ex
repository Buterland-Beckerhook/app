defmodule BbhWeb.DevClockHTML do
  use BbhWeb, :html

  embed_templates "dev_clock_html/*"

  @doc "This page with some of its options (`ansicht`, `breite`, `groesse`) replaced."
  def overview_path(assigns, changes) do
    query =
      %{"ansicht" => assigns.view, "breite" => assigns.width, "groesse" => assigns.size}
      |> Map.merge(changes)

    "/dev/zeitreise?" <> URI.encode_query(query)
  end

  @doc "The frame URL for `path` at moment `at` (appends to an existing query)."
  def frame_src(path, at) do
    sep = if String.contains?(path, "?"), do: "&", else: "?"
    "#{path}#{sep}jetzt=#{BbhWeb.DevClock.param(at)}&jetzt_temp=1"
  end
end
