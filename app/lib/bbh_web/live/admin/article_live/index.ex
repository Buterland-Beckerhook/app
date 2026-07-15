defmodule BbhWeb.Admin.ArticleLive.Index do
  use BbhWeb, :live_view

  alias Bbh.Content
  alias BbhWeb.AdminList

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign(:page_title, "Artikel")
     |> assign(:list_state, AdminList.init(sort: "date_published", dir: :desc))
     |> load_list()}
  end

  @impl true
  def handle_event("list-" <> action, params, socket),
    do: {:noreply, AdminList.handle(action, params, socket, &load_list/1)}

  defp load_list(socket) do
    meta =
      AdminList.process(Content.list_articles(), socket.assigns.list_state,
        search: [& &1.title],
        sort: %{
          "title" => & &1.title,
          "date_published" => & &1.date_published,
          "status" => & &1.status
        }
      )

    assign(socket, articles: meta.entries, list_meta: meta)
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

      <.list_search q={@list_meta.q} placeholder="Nach Titel suchen…" />

      <.table id="articles" rows={@articles} sort={@list_meta.sort} dir={@list_meta.dir}>
        <:col :let={a} label="Titel" sort_key="title">
          <span class="font-medium">{a.title}</span>
        </:col>
        <:col :let={a} label="Datum" sort_key="date_published">{de_date(a.date_published)}</:col>
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
