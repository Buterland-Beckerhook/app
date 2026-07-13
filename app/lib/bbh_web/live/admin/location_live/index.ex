defmodule BbhWeb.Admin.LocationLive.Index do
  use BbhWeb, :live_view

  alias Bbh.Calendar

  @impl true
  def mount(_params, _session, socket) do
    {:ok, assign(socket, page_title: "Orte", locations: Calendar.list_locations())}
  end

  @impl true
  def handle_event("delete", %{"id" => id}, socket) do
    id |> Calendar.get_location!() |> Calendar.delete_location()

    {:noreply,
     socket |> put_flash(:info, "Ort gelöscht.") |> assign(:locations, Calendar.list_locations())}
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

      <.table id="locations" rows={@locations}>
        <:col :let={l} label="Name"><span class="font-medium">{l.name}</span></:col>
        <:col :let={l} label="Ort">{l.city}</:col>
        <:action :let={l}>
          <.link navigate={~p"/admin/orte/#{l.id}/bearbeiten"} class="link link-primary">Bearbeiten</.link>
        </:action>
        <:action :let={l}>
          <.link
            phx-click={JS.push("delete", value: %{id: l.id})}
            data-confirm="Diesen Ort wirklich löschen?"
            class="link link-error"
          >
            Löschen
          </.link>
        </:action>
      </.table>
    </Layouts.admin>
    """
  end
end
