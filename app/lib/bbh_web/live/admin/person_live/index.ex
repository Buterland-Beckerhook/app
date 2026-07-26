defmodule BbhWeb.Admin.PersonLive.Index do
  use BbhWeb, :live_view

  alias Bbh.Club
  alias Bbh.Club.Person
  alias BbhWeb.AdminList

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign(:page_title, "Personen")
     |> assign(:list_state, AdminList.init(sort: nil))
     |> load_list()}
  end

  @impl true
  def handle_event("list-" <> action, params, socket),
    do: {:noreply, AdminList.handle(action, params, socket, &load_list/1)}

  # Two fixed sections instead of a sortable, paginated table: „Aktiv" (no „Amt bis")
  # on top, „Nicht mehr aktiv" below. `Club.list_all_people/0` already orders by
  # `sort_order` then `name`, and `AdminList.process` with `sort: nil` leaves that order
  # untouched — so each section is correctly sorted. Search still filters both; a large
  # `per_page` keeps everything on one page.
  defp load_list(socket) do
    meta =
      AdminList.process(Club.list_all_people(), socket.assigns.list_state,
        search: [& &1.name, & &1.email],
        per_page: 10_000
      )

    {active, inactive} = Enum.split_with(meta.entries, &is_nil(&1.year_end))

    socket
    |> assign(:active_people, active)
    |> assign(:inactive_people, inactive)
    |> assign(:list_meta, meta)
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

      <.list_search q={@list_meta.q} placeholder="Nach Name suchen…" />

      <h2 class="mt-6 mb-2 text-lg font-semibold">Aktiv</h2>
      <.people_table :if={@active_people != []} id="people-active" rows={@active_people} />
      <p :if={@active_people == []} class="text-sm text-base-content/60">Keine aktiven Personen.</p>

      <h2 class="mt-8 mb-2 text-lg font-semibold">Nicht mehr aktiv</h2>
      <.people_table :if={@inactive_people != []} id="people-inactive" rows={@inactive_people} />
      <p :if={@inactive_people == []} class="text-sm text-base-content/60">
        Keine ehemaligen Personen.
      </p>
    </Layouts.admin>
    """
  end

  # Shared person table for both sections. No `sort_key` on the columns — the sections have a
  # fixed order (`sort_order`, then `name`), so headers are not sortable.
  attr :id, :string, required: true
  attr :rows, :list, required: true

  defp people_table(assigns) do
    ~H"""
    <.table id={@id} rows={@rows}>
      <:col :let={p} label="Name"><span class="font-medium">{p.name}</span></:col>
      <:col :let={p} label="Rolle">{Person.role_label(p.role)}</:col>
      <:col :let={p} label="Amtszeit">{amtszeit(p)}</:col>
      <:col :let={p} label="E-Mail">{p.email || "–"}</:col>
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
    </.table>
    """
  end

  defp amtszeit(%{year_start: nil, year_end: nil}), do: "–"
  defp amtszeit(%{year_start: from, year_end: nil}), do: "#{from} – heute"
  defp amtszeit(%{year_start: nil, year_end: to}), do: "bis #{to}"
  defp amtszeit(%{year_start: from, year_end: to}), do: "#{from} – #{to}"
end
