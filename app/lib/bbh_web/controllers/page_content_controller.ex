defmodule BbhWeb.PageContentController do
  use BbhWeb, :controller
  import BbhWeb.ControllerHelpers

  @verein_subpages [
    %{slug: "vorstand", label: "Vorstand"},
    %{slug: "offiziere", label: "Offiziere"},
    %{slug: "jungschuetzen", label: "Jungschützen"},
    %{slug: "kinderfest", label: "Kinderfest"},
    %{slug: "mitglied-werden", label: "Mitglied werden"}
  ]

  def verein(conn, _params) do
    blocks =
      case Bbh.Content.get_published_page("ueber-uns") do
        {_page, blocks} -> blocks
        nil -> []
      end

    render(conn, :verein, page_title: "Verein", blocks: blocks, subpages: @verein_subpages)
  end

  def verein_page(conn, %{"slug" => slug}) do
    page = Bbh.Content.get_published_page(slug)

    people =
      case slug do
        "vorstand" -> Bbh.Club.list_vorstand()
        "offiziere" -> Bbh.Club.list_offiziere()
        _ -> nil
      end

    cond do
      page == nil and people in [nil, []] ->
        not_found(conn)

      true ->
        {page_struct, blocks} = page || {nil, []}
        title = (page_struct && page_struct.title) || subpage_label(slug)

        render(conn, :verein_page,
          page_title: title,
          title: title,
          blocks: blocks,
          people: people
        )
    end
  end

  def impressum(conn, _params), do: render_static(conn, "impressum", "Impressum")
  def datenschutz(conn, _params), do: render_static(conn, "datenschutz", "Datenschutz")

  defp render_static(conn, slug, title) do
    case Bbh.Content.get_published_page(slug) do
      {page, blocks} ->
        render(conn, :page, page_title: page.title || title, title: page.title || title, blocks: blocks)

      nil ->
        not_found(conn)
    end
  end

  defp subpage_label(slug) do
    Enum.find_value(@verein_subpages, slug, fn s -> s.slug == slug && s.label end)
  end
end
