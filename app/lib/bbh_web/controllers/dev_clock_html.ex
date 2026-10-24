defmodule BbhWeb.DevClockHTML do
  use BbhWeb, :html

  embed_templates "dev_clock_html/*"

  @doc "The frame URL for `path` at moment `at` (appends to an existing query)."
  def frame_src(path, at) do
    sep = if String.contains?(path, "?"), do: "&", else: "?"
    "#{path}#{sep}jetzt=#{BbhWeb.DevClock.param(at)}&jetzt_temp=1"
  end
end
