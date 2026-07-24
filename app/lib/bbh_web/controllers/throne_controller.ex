defmodule BbhWeb.ThroneController do
  use BbhWeb, :controller
  import BbhWeb.ControllerHelpers

  # Throne types that get their own paginated list page. Kaiser is intentionally
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

  defp render_list(conn, type, params) do
    meta = @list_types[type]
    result = Bbh.Content.list_thrones(type, page_param(params), 1)
    nav = Bbh.Content.list_throne_nav(type)

    render(conn, :index,
      page_title: meta.title,
      heading: meta.heading,
      base_path: meta.base_path,
      result: result,
      nav: nav
    )
  end
end
