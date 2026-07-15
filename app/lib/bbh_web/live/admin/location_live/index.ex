defmodule BbhWeb.Admin.LocationLive.Index do
  use BbhWeb, :live_view

  alias Bbh.Calendar

  @impl true
  def mount(_params, _session, socket) do
    {:ok, assign(socket, page_title: "Orte", locations: Calendar.list_locations())}
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
    </Layouts.admin>
    """
  end
end
