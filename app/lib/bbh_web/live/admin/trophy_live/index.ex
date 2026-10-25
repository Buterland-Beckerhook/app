defmodule BbhWeb.Admin.TrophyLive.Index do
  @moduledoc """
  „Pokale": the trophies (few, rarely touched) above the winners (one row per trophy and
  year — the list that grows every January and May).
  """
  use BbhWeb, :live_view

  alias Bbh.Club
  alias BbhWeb.AdminList

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign(:page_title, "Pokale")
     |> assign(:trophies, Club.list_trophies())
     |> assign(:list_state, AdminList.init(sort: "year", dir: :desc))
     |> load_list()}
  end

  @impl true
  def handle_event("list-" <> action, params, socket),
    do: {:noreply, AdminList.handle(action, params, socket, &load_list/1)}

  defp load_list(socket) do
    meta =
      AdminList.process(Club.list_trophy_wins(), socket.assigns.list_state,
        search: [& &1.winner, & &1.trophy.name, &Integer.to_string(&1.year)],
        sort: %{
          "year" => & &1.year,
          "trophy" => & &1.trophy.sort_order,
          "winner" => & &1.winner
        }
      )

    assign(socket, wins: meta.entries, list_meta: meta)
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.admin flash={@flash} current_scope={@current_scope} active={:trophies}>
      <.header>
        Pokale
        <:subtitle>
          Die Sieger erscheinen über den Block „Pokalsieger“ auf jeder Seite, die ihn enthält.
        </:subtitle>
        <:actions>
          <.button variant="primary" navigate={~p"/admin/pokale/sieger/neu"}>
            Neuer Sieger
          </.button>
        </:actions>
      </.header>

      <section class="mt-6">
        <div class="flex items-center justify-between">
          <h2 class="text-lg font-semibold">Pokale</h2>
          <.button navigate={~p"/admin/pokale/neu"}>Neuer Pokal</.button>
        </div>
        <ul class="mt-2 divide-y divide-base-300 rounded-box border border-base-300">
          <li :for={t <- @trophies} class="flex items-center justify-between px-4 py-2">
            <span>
              <span class="font-medium">{t.name}</span>
              <span :if={t.since} class="text-sm text-base-content/60">seit {t.since}</span>
            </span>
            <.link
              navigate={~p"/admin/pokale/#{t.id}/bearbeiten"}
              class="link link-primary"
              title="Bearbeiten"
              aria-label={"#{t.name} bearbeiten"}
            >
              <.icon name="hero-pencil-square" class="size-5" />
            </.link>
          </li>
          <li :if={@trophies == []} class="px-4 py-2 text-sm text-base-content/60">
            Noch keine Pokale angelegt.
          </li>
        </ul>
      </section>

      <h2 class="mt-8 text-lg font-semibold">Sieger</h2>
      <.list_search q={@list_meta.q} placeholder="Nach Name, Pokal oder Jahr suchen…" />

      <.table id="trophy-wins" rows={@wins} sort={@list_meta.sort} dir={@list_meta.dir}>
        <:col :let={w} label="Jahr" sort_key="year">{w.year}</:col>
        <:col :let={w} label="Pokal" sort_key="trophy">{w.trophy.name}</:col>
        <:col :let={w} label="Sieger" sort_key="winner">
          <span class="font-medium">{w.winner}</span>
        </:col>
        <:col :let={w} label="Ringe">{w.rings || "–"}</:col>
        <:action :let={w}>
          <.link
            navigate={~p"/admin/pokale/sieger/#{w.id}/bearbeiten"}
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
