defmodule BbhWeb.Admin.DashboardLive do
  use BbhWeb, :live_view

  @impl true
  def mount(_params, _session, socket) do
    stats = %{
      articles: Bbh.Content.count_articles(),
      events: Bbh.Repo.aggregate(Bbh.Calendar.Event, :count, :id),
      people: Bbh.Repo.aggregate(Bbh.Club.Person, :count, :id),
      pages: Bbh.Repo.aggregate(Bbh.Content.Page, :count, :id)
    }

    {:ok, assign(socket, page_title: "Übersicht", stats: stats)}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.admin flash={@flash} current_scope={@current_scope} active={:dashboard}>
      <.header>
        Übersicht
        <:subtitle>Willkommen im Verwaltungsbereich.</:subtitle>
      </.header>

      <div class="mt-6 grid grid-cols-2 gap-4 md:grid-cols-4">
        <.link
          navigate={~p"/admin/artikel"}
          class="rounded-box border border-base-300 bg-base-200 p-4 hover:border-primary"
        >
          <div class="text-3xl font-semibold text-primary">{@stats.articles}</div>
          <div class="text-sm text-base-content/70">Artikel</div>
        </.link>
        <.stat_card label="Termine" value={@stats.events} />
        <.stat_card label="Personen" value={@stats.people} />
        <.stat_card label="Seiten" value={@stats.pages} />
      </div>
    </Layouts.admin>
    """
  end

  attr :label, :string, required: true
  attr :value, :integer, required: true

  defp stat_card(assigns) do
    ~H"""
    <div class="rounded-box border border-base-300 bg-base-200 p-4">
      <div class="text-3xl font-semibold text-primary">{@value}</div>
      <div class="text-sm text-base-content/70">{@label}</div>
    </div>
    """
  end
end
