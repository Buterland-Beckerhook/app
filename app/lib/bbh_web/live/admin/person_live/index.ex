defmodule BbhWeb.Admin.PersonLive.Index do
  use BbhWeb, :live_view

  alias Bbh.Club
  alias Bbh.Club.Person

  @impl true
  def mount(_params, _session, socket) do
    {:ok, assign(socket, page_title: "Personen", people: Club.list_all_people())}
  end

  @impl true
  def handle_event("delete", %{"id" => id}, socket) do
    id |> Club.get_person!() |> Club.delete_person()

    {:noreply,
     socket |> put_flash(:info, "Person gelöscht.") |> assign(:people, Club.list_all_people())}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.admin flash={@flash} current_scope={@current_scope} active={:people}>
      <.header>
        Personen
        <:actions>
          <.button variant="primary" navigate={~p"/admin/personen/neu"}>Neue Person</.button>
        </:actions>
      </.header>

      <.table id="people" rows={@people}>
        <:col :let={p} label="Name"><span class="font-medium">{p.name}</span></:col>
        <:col :let={p} label="Rolle">{Person.role_label(p.role)}</:col>
        <:col :let={p} label="Ehrenmitglied">{if p.honorary_member, do: "ja", else: "–"}</:col>
        <:action :let={p}>
          <.link
            navigate={~p"/admin/personen/#{p.id}/bearbeiten"}
            class="link link-primary"
            title="Bearbeiten"
            aria-label="Bearbeiten"
          >
            <.icon name="hero-pencil-square" class="size-5" />
          </.link>
        </:action>
        <:action :let={p}>
          <.link
            phx-click={JS.push("delete", value: %{id: p.id})}
            data-confirm="Diese Person wirklich löschen?"
            class="link link-error"
            title="Löschen"
            aria-label="Löschen"
          >
            <.icon name="hero-trash" class="size-5" />
          </.link>
        </:action>
      </.table>
    </Layouts.admin>
    """
  end
end
