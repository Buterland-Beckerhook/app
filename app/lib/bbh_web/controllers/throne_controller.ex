defmodule BbhWeb.ThroneController do
  use BbhWeb, :controller
  import BbhWeb.ControllerHelpers

  alias Bbh.Content

  # Throne types that get their own list page. Kaiser is intentionally
  # excluded — Kaiser reigns are surfaced as direct article links in the nav.
  @list_types %{
    "koenig" => %{title: "Throne", heading: "Throne seit 1909", base_path: "/thron"},
    "stadtkaiser" => %{
      title: "Stadtkaiser",
      heading: "Stadtkaiser",
      base_path: "/thron/stadtkaiser"
    },
    "jungschuetzenkoenig" => %{
      title: "Jungschützenkönig",
      heading: "Jungschützenkönig",
      base_path: "/thron/jungschuetzenkoenig"
    }
  }

  def index(conn, params), do: render_list(conn, "koenig", params)

  def index_type(conn, %{"type" => type} = params) when is_map_key(@list_types, type),
    do: render_list(conn, type, params)

  def index_type(conn, _params), do: not_found(conn)

  # One throne per page, addressed by its begin year (`?jahr=1995`) so the URL in the
  # address bar — and thus whatever the OS share sheet hands on — stays valid as new
  # thrones are added. The old position-based `?seite=N` shifted by one every year; it
  # permanently redirects to the `?jahr=` URL of the throne now at that position (best
  # effort: an old link lands where that position points *today*). Without a parameter
  # the newest throne is shown.
  defp render_list(conn, type, params) do
    meta = @list_types[type]
    nav = Content.Thrones.list_throne_nav(type)

    case resolve(type, nav, params) do
      {:show, throne, title} ->
        render(conn, :index,
          page_title: page_title(meta, throne, title),
          heading: meta.heading,
          base_path: meta.base_path,
          throne: throne,
          nav: nav
        )

      {:redirect, query} ->
        conn
        |> put_status(:moved_permanently)
        |> redirect(to: meta.base_path <> query)

      :not_found ->
        not_found(conn)
    end
  end

  defp resolve(type, _nav, %{"jahr" => jahr}) do
    with {year, ""} <- Integer.parse(jahr),
         %{} = throne <- Content.Thrones.get_throne_by_year(type, year) do
      {:show, throne, :with_years}
    else
      _ -> :not_found
    end
  end

  defp resolve(_type, nav, %{"seite" => _} = params) do
    case Enum.at(nav, page_param(params) - 1) do
      %{begin_year: year} -> {:redirect, "?jahr=#{year}"}
      nil -> {:redirect, ""}
    end
  end

  defp resolve(type, nav, _params) do
    case nav do
      [%{begin_year: year} | _] -> {:show, Content.Thrones.get_throne_by_year(type, year), :plain}
      [] -> {:show, nil, :plain}
    end
  end

  # A throne addressed by year gets its own tab/share title ("Throne 1995–1996"); the
  # bare list URL always shows the newest throne, so it keeps the section title.
  defp page_title(meta, throne, :with_years),
    do: "#{meta.title} #{BbhWeb.SiteComponents.throne_years(throne)}"

  defp page_title(meta, _throne, :plain), do: meta.title
end
