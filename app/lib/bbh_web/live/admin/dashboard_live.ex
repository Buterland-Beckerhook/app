defmodule BbhWeb.Admin.DashboardLive do
  use BbhWeb, :live_view

  @ranges [7, 30, 90]

  @impl true
  def mount(_params, _session, socket) do
    is_admin = Bbh.Accounts.User.admin?(socket.assigns.current_scope.user)

    socket =
      socket
      |> assign(page_title: "Übersicht", is_admin: is_admin, range_days: 30)
      |> assign_async(:stats, &load_stats/0)

    {:ok, if(is_admin, do: load_analytics(socket), else: socket)}
  end

  @impl true
  def handle_event("set_range", %{"days" => days}, socket) do
    days = if String.to_integer(days) in @ranges, do: String.to_integer(days), else: 30
    {:noreply, socket |> assign(range_days: days) |> load_analytics()}
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

  defp load_analytics(socket) do
    days = socket.assigns.range_days

    assign_async(socket, :analytics, fn ->
      to = Date.utc_today()
      from = Date.add(to, -(days - 1))

      {:ok,
       %{
         analytics: %{
           summary: Bbh.Analytics.summary(from, to),
           by_day: Bbh.Analytics.views_by_day(from, to),
           top_pages: Bbh.Analytics.top_pages(from, to),
           top_referrers: Bbh.Analytics.top_referrers(from, to)
         }
       }}
    end)
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

      <section :if={@is_admin} class="mt-10">
        <div class="flex flex-wrap items-center justify-between gap-2">
          <h2 class="text-lg font-semibold">Zugriffe</h2>
          <div class="join">
            <button
              :for={d <- [7, 30, 90]}
              type="button"
              phx-click="set_range"
              phx-value-days={d}
              class={["btn btn-sm join-item", @range_days == d && "btn-active"]}
            >
              {d} Tage
            </button>
          </div>
        </div>

        <.async_result :let={a} assign={@analytics}>
          <:loading>
            <div class="mt-4 h-40 animate-pulse rounded-box bg-base-200"></div>
          </:loading>
          <:failed :let={_reason}>
            <p class="mt-4 text-error">Zugriffsstatistik konnte nicht geladen werden.</p>
          </:failed>

          <div class="mt-4 grid grid-cols-2 gap-4 md:max-w-sm">
            <div class="rounded-box border border-base-300 bg-base-200 p-4">
              <div class="text-3xl font-semibold text-primary">{a.summary.views}</div>
              <div class="text-sm text-base-content/70">Seitenaufrufe</div>
            </div>
            <div class="rounded-box border border-base-300 bg-base-200 p-4">
              <div class="text-3xl font-semibold text-primary">{a.summary.visits}</div>
              <div class="text-sm text-base-content/70" title="Summe der täglichen Besucher">
                Besuche
              </div>
            </div>
          </div>

          <div class="mt-6 rounded-box border border-base-300 bg-base-200 p-4">
            <div class="mb-2 text-sm text-base-content/70">Aufrufe pro Tag</div>
            <% max = day_max(a.by_day) %>
            <div class="flex h-32 items-end gap-px">
              <div
                :for={point <- a.by_day}
                class="flex-1 rounded-t bg-primary/70 hover:bg-primary"
                style={"height: #{bar_pct(point.count, max)}%"}
                title={"#{Calendar.strftime(point.day, "%d.%m.")}: #{point.count}"}
              >
              </div>
            </div>
          </div>

          <div class="mt-6 grid gap-6 md:grid-cols-2">
            <.top_list title="Top-Seiten" rows={a.top_pages} key={:path} empty="Noch keine Aufrufe." />
            <.top_list
              title="Top-Verweise"
              rows={a.top_referrers}
              key={:host}
              empty="Keine externen Verweise."
            />
          </div>
        </.async_result>
      </section>
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

  attr :title, :string, required: true
  attr :rows, :list, required: true
  attr :key, :atom, required: true
  attr :empty, :string, required: true

  defp top_list(assigns) do
    ~H"""
    <div class="rounded-box border border-base-300 bg-base-200 p-4">
      <div class="mb-2 text-sm font-medium">{@title}</div>
      <p :if={@rows == []} class="text-sm text-base-content/60">{@empty}</p>
      <ul class="space-y-1">
        <li :for={row <- @rows} class="flex items-center justify-between gap-3 text-sm">
          <span class="truncate text-base-content/80">{Map.get(row, @key)}</span>
          <span class="shrink-0 font-medium tabular-nums">{row.views}</span>
        </li>
      </ul>
    </div>
    """
  end

  defp day_max(by_day), do: by_day |> Enum.map(& &1.count) |> Enum.max(fn -> 0 end)

  defp bar_pct(0, _max), do: 0
  defp bar_pct(_count, 0), do: 0
  defp bar_pct(count, max), do: max(round(count / max * 100), 2)
end
