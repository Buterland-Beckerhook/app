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
     |> assign(:list_state, AdminList.init(sort: "sort_order", dir: :asc))
     |> load_list()}
  end

  @impl true
  def handle_event("list-" <> action, params, socket),
    do: {:noreply, AdminList.handle(action, params, socket, &load_list/1)}

  defp load_list(socket) do
    meta =
      AdminList.process(Club.list_all_people(), socket.assigns.list_state,
        search: [& &1.name, & &1.email],
        sort: %{
          "name" => & &1.name,
          "role" => &Person.role_label(&1.role),
          "sort_order" => & &1.sort_order
        }
      )

    assign(socket, people: meta.entries, list_meta: meta)
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

      <.table id="people" rows={@people} sort={@list_meta.sort} dir={@list_meta.dir}>
        <:col :let={p} label="Name" sort_key="name"><span class="font-medium">{p.name}</span></:col>
        <:col :let={p} label="Rolle" sort_key="role">{Person.role_label(p.role)}</:col>
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

      <.list_pagination meta={@list_meta} />
    </Layouts.admin>
    """
  end
end
