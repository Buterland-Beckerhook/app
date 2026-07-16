defmodule BbhWeb.Admin.PageLive.Index do
  use BbhWeb, :live_view

  alias Bbh.Content
  alias BbhWeb.AdminList

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign(:page_title, "Seiten")
     |> assign(:list_state, AdminList.init(sort: "sort_order", dir: :asc))
     |> load_list()}
  end

  @impl true
  def handle_event("list-" <> action, params, socket),
    do: {:noreply, AdminList.handle(action, params, socket, &load_list/1)}

  defp load_list(socket) do
    meta =
      AdminList.process(Content.list_pages(), socket.assigns.list_state,
        search: [& &1.title, & &1.slug],
        sort: %{
          "title" => & &1.title,
          "slug" => & &1.slug,
          "status" => & &1.status,
          "sort_order" => & &1.sort_order
        }
      )

    assign(socket, pages: meta.entries, list_meta: meta)
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.admin flash={@flash} current_scope={@current_scope} active={:pages}>
      <.header>
        Seiten
        <:actions>
          <.button variant="primary" navigate={~p"/admin/seiten/neu"}>Neue Seite</.button>
        </:actions>
      </.header>

      <.list_search q={@list_meta.q} placeholder="Nach Titel suchen…" />

      <.table id="pages" rows={@pages} sort={@list_meta.sort} dir={@list_meta.dir}>
        <:col :let={p} label="Titel" sort_key="title">
          <span class="font-medium">{p.title}</span>
        </:col>
        <:col :let={p} label="Slug" sort_key="slug">{p.slug}</:col>
        <:col :let={p} label="Status" sort_key="status">
          <.status_badge status={p.status} />
        </:col>
        <:action :let={p}>
          <.link
            navigate={~p"/admin/seiten/#{p.id}/bearbeiten"}
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
