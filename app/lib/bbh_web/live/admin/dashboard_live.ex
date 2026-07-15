defmodule BbhWeb.Admin.DashboardLive do
  use BbhWeb, :live_view

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign(page_title: "Übersicht")
     |> assign_async(:stats, &load_stats/0)}
  end

  # Runs off the connected mount so the page shell renders without blocking on the DB.
  defp load_stats do
    {:ok,
     %{
       stats: %{
         articles: Bbh.Content.count_articles(),
         events: Bbh.Repo.aggregate(Bbh.Calendar.Event, :count, :id),
         people: Bbh.Repo.aggregate(Bbh.Club.Person, :count, :id),
         pages: Bbh.Repo.aggregate(Bbh.Content.Page, :count, :id)
       }
     }}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.admin flash={@flash} current_scope={@current_scope} active={:dashboard}>
      <.header>
        Übersicht
        <:subtitle>Willkommen im Verwaltungsbereich.</:subtitle>
      </.header>

      <.async_result :let={stats} assign={@stats}>
        <:loading>
          <div class="mt-6 grid grid-cols-2 gap-4 md:grid-cols-4">
            <div :for={_ <- 1..4} class="h-20 animate-pulse rounded-box bg-base-200"></div>
          </div>
        </:loading>
        <:failed :let={_reason}>
          <p class="mt-6 text-error">Statistik konnte nicht geladen werden.</p>
        </:failed>

        <% user = @current_scope.user %>
        <div class="mt-6 grid grid-cols-2 gap-4 md:grid-cols-4">
          <.stat_card
            :if={BbhWeb.Authz.can_access_section?(user, :articles)}
            label="Artikel"
            value={stats.articles}
            navigate={~p"/admin/artikel"}
          />
          <.stat_card label="Termine" value={stats.events} navigate={~p"/admin/termine"} />
          <.stat_card
            :if={BbhWeb.Authz.can_access_section?(user, :people)}
            label="Personen"
            value={stats.people}
            navigate={~p"/admin/personen"}
          />
          <.stat_card
            :if={BbhWeb.Authz.can_access_section?(user, :pages)}
            label="Seiten"
            value={stats.pages}
            navigate={~p"/admin/seiten"}
          />
        </div>
      </.async_result>
    </Layouts.admin>
    """
  end

  attr :label, :string, required: true
  attr :value, :integer, required: true
  attr :navigate, :string, required: true

  defp stat_card(assigns) do
    ~H"""
    <.link
      navigate={@navigate}
      class="rounded-box border border-base-300 bg-base-200 p-4 hover:border-primary"
    >
      <div class="text-3xl font-semibold text-primary">{@value}</div>
      <div class="text-sm text-base-content/70">{@label}</div>
    </.link>
    """
  end
end
