defmodule BbhWeb.Admin.EventLive.Index do
  use BbhWeb, :live_view

  alias Bbh.Calendar
  alias Bbh.Calendar.Event
  alias BbhWeb.AdminList

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign(:page_title, "Termine")
     |> assign(:list_state, AdminList.init(sort: "starts_at", dir: :desc))
     |> assign(:expanded, MapSet.new())
     |> load_list()}
  end

  @impl true
  def handle_event("list-" <> action, params, socket),
    do: {:noreply, AdminList.handle(action, params, socket, &load_list/1)}

  def handle_event("toggle-programme", %{"id" => id}, socket) do
    expanded = socket.assigns.expanded

    expanded =
      if MapSet.member?(expanded, id),
        do: MapSet.delete(expanded, id),
        else: MapSet.put(expanded, id)

    {:noreply, socket |> assign(:expanded, expanded) |> show_rows()}
  end

  # Programme items are listed under their festival (collapsed by default), not on
  # their own: filtering, sorting and paging apply to top-level events, and a search
  # hit on an item finds its festival.
  defp load_list(socket) do
    {items, events} =
      socket.assigns.current_scope.user
      |> Calendar.list_events_for()
      |> Enum.split_with(& &1.parent_id)

    programmes =
      items
      |> Enum.sort_by(& &1.starts_at, DateTime)
      |> Enum.group_by(& &1.parent_id)

    meta =
      AdminList.process(events, socket.assigns.list_state,
        search: [
          & &1.title,
          &(programmes |> Map.get(&1.id, []) |> Enum.map_join(" ", fn item -> item.title end))
        ],
        category: {&(&1.calendar || "public"), socket.assigns.list_state.cat},
        sort: %{
          "title" => & &1.title,
          "starts_at" => & &1.starts_at,
          "status" => & &1.status
        }
      )

    socket
    |> assign(list_meta: meta, top_level: meta.entries, programmes: programmes)
    |> show_rows()
  end

  defp show_rows(socket) do
    %{top_level: top_level, programmes: programmes, expanded: expanded} = socket.assigns

    rows =
      Enum.flat_map(top_level, fn event ->
        if MapSet.member?(expanded, event.id),
          do: [event | Map.get(programmes, event.id, [])],
          else: [event]
      end)

    assign(socket, :events, rows)
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

      <div class="flex flex-wrap items-center gap-2">
        <.list_search q={@list_meta.q} placeholder="Nach Titel suchen…" />
        <form id="event-cat-filter" phx-change="list-filter-cat">
          <select name="cat" class="select select-sm select-bordered" aria-label="Kalender filtern">
            <option value="" selected={@list_meta.cat in [nil, ""]}>Alle Kalender</option>
            <option value="public" selected={@list_meta.cat == "public"}>Öffentlich</option>
            <option
              :for={c <- Event.calendars()}
              value={c}
              selected={@list_meta.cat == c}
            >
              {Event.calendar_label(c)}
            </option>
          </select>
        </form>
      </div>

      <.table id="events" rows={@events} sort={@list_meta.sort} dir={@list_meta.dir}>
        <:col :let={e} label="Titel" sort_key="title">
          <%= if e.parent_id do %>
            <span class="pl-5 text-base-content/80">↳ {e.title}</span>
          <% else %>
            <span class="font-medium">{e.title}</span>
            <% count = length(Map.get(@programmes, e.id, [])) %>
            <button
              :if={count > 0}
              type="button"
              phx-click="toggle-programme"
              phx-value-id={e.id}
              class="ml-2 badge badge-sm badge-outline cursor-pointer"
              aria-expanded={to_string(MapSet.member?(@expanded, e.id))}
            >
              {if MapSet.member?(@expanded, e.id), do: "▾", else: "▸"}
              {BbhWeb.EventHTML.programme_count(count)}
            </button>
          <% end %>
        </:col>
        <:col :let={e} label="Beginn" sort_key="starts_at">{de_datetime(e.starts_at)}</:col>
        <:col :let={e} label="Kalender">
          <span class={["badge badge-sm", if(e.calendar, do: "badge-secondary", else: "badge-ghost")]}>
            {if e.calendar, do: Event.calendar_label(e.calendar), else: "Öffentlich"}
          </span>
        </:col>
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
