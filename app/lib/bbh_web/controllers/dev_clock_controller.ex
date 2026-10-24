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
  # {frame width, frame height, base scale} per device, and a zoom factor per size.
  @widths %{"desktop" => {1280, 800, 0.4}, "mobil" => {390, 844, 0.75}}
  @sizes [{"klein", "S", 0.65}, {"mittel", "M", 1.0}, {"gross", "L", 1.5}]

  def index(conn, params) do
    fest = Bbh.Calendar.dev_festival()

    view =
      if params["ansicht"] in Enum.map(@views, &elem(&1, 0)), do: params["ansicht"], else: "start"

    width = if Map.has_key?(@widths, params["breite"]), do: params["breite"], else: "desktop"
    size = Enum.find(@sizes, Enum.at(@sizes, 1), &(elem(&1, 0) == params["groesse"]))
    {w, h, scale} = Map.fetch!(@widths, width)

    render(conn, :index,
      page_title: "Zeitreise",
      fest: fest,
      points: DevClock.overview_points(fest),
      views: @views,
      view: view,
      width: width,
      sizes: @sizes,
      size: elem(size, 0),
      frame: {w, h, scale * elem(size, 2)},
      path: page_path(view, fest)
    )
  end

  defp page_path("fest", %{year: year, slug: slug}), do: "/termine/#{year}/#{slug}"
  defp page_path("termine", %{year: year}), do: "/termine?jahr=#{year}"
  defp page_path(_, _), do: "/"
end
