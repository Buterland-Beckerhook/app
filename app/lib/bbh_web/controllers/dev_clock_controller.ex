defmodule BbhWeb.DevClockController do
  @moduledoc """
  `/dev/zeitreise` (dev routes only): a grid of iframes showing one page of the site
  at many simulated moments of `Bbh.Calendar.dev_festival/1` — the whole festival at
  a glance. Each frame loads its page with `?jetzt=<t>&jetzt_temp=1`; see
  `BbhWeb.Plugs.DevClock`.
  """
  use BbhWeb, :controller

  alias BbhWeb.DevClock

  @views [{"start", "Startseite"}, {"fest", "Festseite"}, {"termine", "Terminliste"}]
  @widths %{"desktop" => {1280, 900, 0.3}, "mobil" => {390, 844, 0.45}}

  def index(conn, params) do
    fest = Bbh.Calendar.dev_festival()

    view =
      if params["ansicht"] in Enum.map(@views, &elem(&1, 0)), do: params["ansicht"], else: "start"

    width = if Map.has_key?(@widths, params["breite"]), do: params["breite"], else: "desktop"

    render(conn, :index,
      page_title: "Zeitreise",
      fest: fest,
      points: DevClock.overview_points(fest),
      views: @views,
      view: view,
      width: width,
      frame: Map.fetch!(@widths, width),
      path: page_path(view, fest)
    )
  end

  defp page_path("fest", %{year: year, slug: slug}), do: "/termine/#{year}/#{slug}"
  defp page_path("termine", %{year: year}), do: "/termine?jahr=#{year}"
  defp page_path(_, _), do: "/"
end
