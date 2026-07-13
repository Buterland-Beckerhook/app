defmodule BbhWeb.Admin.EventLive.Index do
  use BbhWeb, :live_view

  alias Bbh.Calendar

  @impl true
  def mount(_params, _session, socket) do
    {:ok, assign(socket, page_title: "Termine", events: Calendar.list_events())}
  end

  @impl true
  def handle_event("delete", %{"id" => id}, socket) do
    id |> Calendar.get_event!() |> Calendar.delete_event()

    {:noreply,
     socket |> put_flash(:info, "Termin gelöscht.") |> assign(:events, Calendar.list_events())}
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

      <.table id="events" rows={@events}>
        <:col :let={e} label="Titel"><span class="font-medium">{e.title}</span></:col>
        <:col :let={e} label="Beginn">{de_datetime(e.starts_at)}</:col>
        <:col :let={e} label="Ort">{e.location && e.location.name}</:col>
        <:col :let={e} label="Status">{status_label(e.status)}</:col>
        <:action :let={e}>
          <.link navigate={~p"/admin/termine/#{e.id}/bearbeiten"} class="link link-primary">Bearbeiten</.link>
        </:action>
        <:action :let={e}>
          <.link
            phx-click={JS.push("delete", value: %{id: e.id})}
            data-confirm="Diesen Termin wirklich löschen?"
            class="link link-error"
          >
            Löschen
          </.link>
        </:action>
      </.table>
    </Layouts.admin>
    """
  end

  defp status_label("published"), do: "Veröffentlicht"
  defp status_label("canceled"), do: "Abgesagt"
  defp status_label(_), do: "Entwurf"
end
