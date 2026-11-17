defmodule BbhWeb.Admin.ArticleLive.Index do
  use BbhWeb, :live_view

  alias Bbh.Content
  alias BbhWeb.AdminList

  # Window of the "Aufrufe" column.
  @views_days 30

  @impl true
  def mount(params, _session, socket) do
    {:ok,
     socket
     |> assign(:page_title, "Artikel")
     |> assign(:views_days, @views_days)
     |> assign(:views, article_views())
     |> assign(
       :list_state,
       AdminList.init(
         sort: "date_published",
         dir: :desc,
         status: AdminList.known(params["status"], Content.Article.statuses())
       )
     )
     |> load_list()}
  end

  @impl true
  def handle_event("list-" <> action, params, socket),
    do: {:noreply, AdminList.handle(action, params, socket, &load_list/1)}

  defp load_list(socket) do
    meta =
      AdminList.process(Content.list_articles(), socket.assigns.list_state,
        search: [& &1.title],
        status: & &1.status,
        sort: %{
          "title" => & &1.title,
          "date_published" => & &1.date_published,
          "status" => & &1.status,
          "views" => &Map.get(socket.assigns.views, &1.id, 0)
        }
      )

    assign(socket, articles: meta.entries, list_meta: meta)
  end

  # Page views per article over the last @views_days days, today included.
  defp article_views do
    to = Date.utc_today()
    Bbh.Analytics.article_views(Date.add(to, -(@views_days - 1)), to)
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.admin flash={@flash} current_scope={@current_scope} active={:articles}>
      <.header>
        Artikel
        <:actions>
          <.button variant="primary" navigate={~p"/admin/artikel/neu"}>Neuer Artikel</.button>
        </:actions>
      </.header>

      <div class="flex flex-wrap items-center gap-2">
        <.list_search q={@list_meta.q} placeholder="Nach Titel suchen…" />
        <.list_status_filter status={@list_meta.status} statuses={Content.Article.statuses()} />
      </div>

      <.table id="articles" rows={@articles} sort={@list_meta.sort} dir={@list_meta.dir}>
        <:col :let={a} label="Titel" sort_key="title">
          <span class="font-medium">{a.title}</span>
        </:col>
        <:col :let={a} label="Datum" sort_key="date_published">{de_date(a.date_published)}</:col>
        <:col :let={a} label={"Aufrufe (#{@views_days} Tage)"} sort_key="views">
          <span class="tabular-nums">{Map.get(@views, a.id, 0)}</span>
        </:col>
        <:col :let={a} label="Status" sort_key="status">
          <.status_badge status={a.status} />
        </:col>
        <:action :let={a}>
          <.link
            navigate={~p"/admin/artikel/#{a.id}/bearbeiten"}
            class="link link-primary"
            title="Bearbeiten"
            aria-label="Bearbeiten"
          >
            <.icon name="hero-pencil-square" class="size-5" />
          </.link>
        </:action>
      </.table>

      <.list_pagination meta={@list_meta} />
    </Layouts.admin>
    """
  end
end
