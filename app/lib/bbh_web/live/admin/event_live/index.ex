defmodule BbhWeb.Admin.EventLive.Index do
  use BbhWeb, :live_view

  alias Bbh.Calendar
  alias BbhWeb.AdminList

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign(:page_title, "Termine")
     |> assign(:list_state, AdminList.init(sort: "starts_at", dir: :desc))
     |> load_list()}
  end

  @impl true
  def handle_event("list-" <> action, params, socket),
    do: {:noreply, AdminList.handle(action, params, socket, &load_list/1)}

  defp load_list(socket) do
    events = Calendar.list_events_for(socket.assigns.current_scope.user)

    meta =
      AdminList.process(events, socket.assigns.list_state,
        search: [& &1.title],
        sort: %{
          "title" => & &1.title,
          "starts_at" => & &1.starts_at,
          "status" => & &1.status
        }
      )

    assign(socket, events: meta.entries, list_meta: meta)
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.admin flash={@flash} current_scope={@current_scope} active={:events}>
      <.header>
        Termine
        <:actions>
          <.button variant="primary" navigate={~p"/admin/termine/neu"}>Neuer Termin</.button>
        </:actions>
      </.header>

      <.list_search q={@list_meta.q} placeholder="Nach Titel suchen…" />

      <.table id="events" rows={@events} sort={@list_meta.sort} dir={@list_meta.dir}>
        <:col :let={e} label="Titel" sort_key="title">
          <span class="font-medium">{e.title}</span>
        </:col>
        <:col :let={e} label="Beginn" sort_key="starts_at">{de_datetime(e.starts_at)}</:col>
        <:col :let={e} label="Ort">{e.location && e.location.name}</:col>
        <:col :let={e} label="Status" sort_key="status"><.status_badge status={e.status} /></:col>
        <:action :let={e}>
          <.link
            navigate={~p"/admin/termine/#{e.id}/bearbeiten"}
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
