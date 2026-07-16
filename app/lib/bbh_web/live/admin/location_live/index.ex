defmodule BbhWeb.Admin.LocationLive.Index do
  use BbhWeb, :live_view

  alias Bbh.Calendar
  alias BbhWeb.AdminList

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign(:page_title, "Orte")
     |> assign(:list_state, AdminList.init(sort: "name", dir: :asc))
     |> load_list()}
  end

  @impl true
  def handle_event("list-" <> action, params, socket),
    do: {:noreply, AdminList.handle(action, params, socket, &load_list/1)}

  defp load_list(socket) do
    meta =
      AdminList.process(Calendar.list_locations(), socket.assigns.list_state,
        search: [& &1.name, & &1.city],
        sort: %{"name" => & &1.name, "city" => & &1.city}
      )

    assign(socket, locations: meta.entries, list_meta: meta)
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.admin flash={@flash} current_scope={@current_scope} active={:locations}>
      <.header>
        Orte
        <:actions>
          <.button variant="primary" navigate={~p"/admin/orte/neu"}>Neuer Ort</.button>
        </:actions>
      </.header>

      <.list_search q={@list_meta.q} placeholder="Nach Name suchen…" />

      <.table id="locations" rows={@locations} sort={@list_meta.sort} dir={@list_meta.dir}>
        <:col :let={l} label="Name" sort_key="name"><span class="font-medium">{l.name}</span></:col>
        <:col :let={l} label="Ort" sort_key="city">{l.city}</:col>
        <:action :let={l}>
          <.link
            navigate={~p"/admin/orte/#{l.id}/bearbeiten"}
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
