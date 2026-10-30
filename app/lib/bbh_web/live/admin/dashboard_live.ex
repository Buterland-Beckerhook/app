defmodule BbhWeb.Admin.DashboardLive do
  use BbhWeb, :live_view

  @ranges [7, 30, 90]

  @impl true
  def mount(_params, _session, socket) do
    scope = socket.assigns.current_scope
    is_admin = Bbh.Accounts.User.admin?(scope.user)

    socket =
      socket
      |> assign(page_title: "Übersicht", is_admin: is_admin, range_days: 30)
      |> assign_async(:stats, &load_stats/0)
      |> assign_tickets(scope)

    {:ok, if(is_admin, do: load_analytics(socket), else: socket)}
  end

  @impl true
  def handle_event("set_range", %{"days" => days}, socket) do
    days = if String.to_integer(days) in @ranges, do: String.to_integer(days), else: 30
    {:noreply, socket |> assign(range_days: days) |> load_analytics()}
  end

  # The Postfach widget: new tickets in the user's queues and the ones assigned to them.
  defp assign_tickets(socket, scope) do
    if BbhWeb.Authz.can_access_tickets?(scope) do
      assign(socket,
        tickets: %{new: Bbh.Tickets.count_new(scope), mine: Bbh.Tickets.list_assigned(scope)}
      )
    else
      assign(socket, tickets: nil)
    end
  end

  # Runs off the connected mount so the page shell renders without blocking on the DB.
  defp load_stats do
    {:ok,
     %{
       stats: %{
         articles: Bbh.Content.count_articles_by_status(),
         events: Bbh.Calendar.count_events_by_status(),
         people: Bbh.Club.count_people(),
         pages: Bbh.Content.count_pages_by_status()
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
           ical: Bbh.Analytics.ical_summary(from, to),
           ical_clients: Bbh.Analytics.ical_clients(from, to),
           push_subscriptions: Bbh.Notifications.count_subscriptions(),
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

      <section :if={@tickets} id="tickets-widget" class="mt-6 rounded-box border border-base-300 p-4">
        <div class="flex flex-wrap items-baseline justify-between gap-2">
          <h2 class="text-lg font-semibold">Postfach</h2>
          <.link navigate={~p"/admin/postfach"} class="link text-sm">
            {@tickets.new} neue Anfrage{if @tickets.new != 1, do: "n"}
          </.link>
        </div>
        <p :if={@tickets.mine == []} class="mt-2 text-sm text-base-content/60">
          Dir ist gerade nichts zugewiesen.
        </p>
        <ul :if={@tickets.mine != []} class="mt-2 space-y-1 text-sm">
          <li :for={t <- @tickets.mine} class="flex flex-wrap items-center gap-2">
            <.link
              navigate={~p"/admin/postfach/#{Bbh.Tickets.Ticket.reference(t)}"}
              class="link font-mono"
            >
              {Bbh.Tickets.Ticket.reference(t)}
            </.link>
            <span>{t.subject}</span>
            <.status_badge kind={:ticket} status={t.status} />
          </li>
        </ul>
      </section>

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
            value={total(stats.articles)}
            breakdown={status_breakdown(stats.articles)}
            navigate={~p"/admin/artikel"}
          />
          <.stat_card
            :if={BbhWeb.Authz.can_access_section?(user, :events)}
            label="Termine"
            value={total(stats.events)}
            breakdown={status_breakdown(stats.events)}
            navigate={~p"/admin/termine"}
          />
          <.stat_card
            :if={BbhWeb.Authz.can_access_section?(user, :people)}
            label="Personen"
            value={stats.people}
            navigate={~p"/admin/personen"}
          />
          <.stat_card
            :if={BbhWeb.Authz.can_access_section?(user, :pages)}
            label="Seiten"
            value={total(stats.pages)}
            breakdown={status_breakdown(stats.pages)}
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
            <div class="rounded-box border border-base-300 bg-base-200 p-4">
              <div class="text-3xl font-semibold text-primary">{a.ical.fetches}</div>
              <div class="text-sm text-base-content/70" title="Abrufe des Termin-Abo-Feeds (.ics)">
                iCal-Abrufe
              </div>
            </div>
            <div class="rounded-box border border-base-300 bg-base-200 p-4">
              <div class="text-3xl font-semibold text-primary">{a.ical.subscribers}</div>
              <div
                class="text-sm text-base-content/70"
                title="Verschiedene Kalender-Clients am aktivsten Tag"
              >
                iCal-Abos
              </div>
            </div>
            <div class="rounded-box border border-base-300 bg-base-200 p-4">
              <div class="text-3xl font-semibold text-primary">{a.push_subscriptions}</div>
              <div class="text-sm text-base-content/70" title="Aktive Push-Benachrichtigungs-Abos">
                Push-Abos
              </div>
            </div>
          </div>

          <div class="mt-6 rounded-box border border-base-300 bg-base-200 p-4">
            <% peak = day_max(a.by_day) %>
            <% top = nice_ceil(peak) %>
            <div class="mb-2 flex items-baseline justify-between gap-2 text-sm text-base-content/70">
              <span>Aufrufe pro Tag</span>
              <span :if={peak > 0} class="text-xs tabular-nums">
                Ø {day_avg(a.by_day)} · Spitze {peak}
              </span>
            </div>
            <div class="flex gap-2">
              <div class="flex h-32 w-8 shrink-0 flex-col justify-between text-right text-[10px] text-base-content/50 tabular-nums">
                <span>{top}</span>
                <span>{round(top / 2)}</span>
                <span>0</span>
              </div>
              <div class="relative flex h-32 flex-1 items-end gap-px">
                <div class="pointer-events-none absolute inset-x-0 top-1/2 border-t border-base-content/10">
                </div>
                <div
                  :for={point <- a.by_day}
                  class="flex-1 rounded-t bg-primary/70 hover:bg-primary"
                  style={"height: #{bar_pct(point.count, top)}%"}
                  title={"#{Calendar.strftime(point.day, "%d.%m.")}: #{point.count}"}
                >
                </div>
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

          <.ical_clients rows={a.ical_clients} />
        </.async_result>
      </section>
    </Layouts.admin>
    """
  end

  attr :label, :string, required: true
  attr :value, :integer, required: true
  attr :navigate, :string, required: true
  attr :breakdown, :list, default: [], doc: "`{status, label, count, class}` tuples"

  # A card, not one big link: each status count links to the list filtered by it, and
  # links can't nest.
  defp stat_card(assigns) do
    ~H"""
    <div class="rounded-box border border-base-300 bg-base-200 p-4 hover:border-primary">
      <.link navigate={@navigate} class="block">
        <div class="text-3xl font-semibold text-primary">{@value}</div>
        <div class="text-sm text-base-content/70">{@label}</div>
      </.link>
      <div :if={@breakdown != []} class="mt-2 flex flex-wrap gap-x-3 gap-y-1 text-xs">
        <.link
          :for={{status, label, count, class} <- @breakdown}
          navigate={"#{@navigate}?#{URI.encode_query(status: status)}"}
          class={["hover:underline", class]}
        >
          <span class="font-semibold tabular-nums">{count}</span> {label}
        </.link>
      </div>
    </div>
    """
  end

  defp total(by_status), do: by_status |> Map.values() |> Enum.sum()

  # Drafts are what an editor still has to finish, so they get the warning colour;
  # "Abgesagt" only shows up once something is canceled.
  defp status_breakdown(by_status) do
    drafts = Map.get(by_status, "draft", 0)
    canceled = Map.get(by_status, "canceled", 0)

    [
      {"published", "veröffentlicht", Map.get(by_status, "published", 0), "text-success"},
      {"draft", draft_label(drafts), drafts, "text-warning"}
    ] ++
      if(canceled > 0,
        do: [{"canceled", "abgesagt", canceled, "text-base-content/60"}],
        else: []
      )
  end

  defp draft_label(1), do: "Entwurf"
  defp draft_label(_), do: "Entwürfe"

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

  attr :rows, :list, required: true

  # iCal subscriptions per calendar-client family. Only the family is known — the
  # feed is anonymous and the visitor hash rotates daily, so there are no per-person IDs.
  defp ical_clients(assigns) do
    ~H"""
    <div id="ical-clients" class="mt-6 rounded-box border border-base-300 bg-base-200 p-4">
      <div class="mb-2 flex items-baseline justify-between gap-3 text-sm">
        <span class="font-medium">iCal-Abos nach Kalender-App</span>
        <span class="text-xs text-base-content/60">Abos · Abrufe</span>
      </div>
      <p :if={@rows == []} class="text-sm text-base-content/60">Keine Abrufe im Zeitraum.</p>
      <ul class="space-y-1">
        <li :for={row <- @rows} class="flex items-center justify-between gap-3 text-sm">
          <span class="truncate text-base-content/80">{row.label}</span>
          <span class="shrink-0 tabular-nums">
            <span class="font-medium">{row.subscribers}</span>
            <span class="text-base-content/60">· {row.fetches}</span>
          </span>
        </li>
      </ul>
      <p :if={@rows != []} class="mt-3 text-xs text-base-content/60">
        Abos = verschiedene Clients am aktivsten Tag. Google und Outlook.com rufen den Feed
        zentral über eigene Server ab – ein Eintrag steht dort für viele Nutzer.
      </p>
    </div>
    """
  end

  defp day_max(by_day), do: by_day |> Enum.map(& &1.count) |> Enum.max(fn -> 0 end)

  defp day_avg([]), do: 0

  defp day_avg(by_day) do
    total = by_day |> Enum.map(& &1.count) |> Enum.sum()
    round(total / length(by_day))
  end

  # Round the axis maximum up to a tidy 1/2/5 × 10ⁿ so the scale reads cleanly and
  # the tallest bar doesn't peg at 100%.
  defp nice_ceil(n) when n <= 0, do: 0

  defp nice_ceil(n) do
    mag = magnitude(n)

    nice =
      cond do
        n <= mag -> 1
        n <= 2 * mag -> 2
        n <= 5 * mag -> 5
        true -> 10
      end

    nice * mag
  end

  defp magnitude(n) when n < 10, do: 1
  defp magnitude(n), do: 10 * magnitude(div(n, 10))

  defp bar_pct(0, _max), do: 0
  defp bar_pct(_count, 0), do: 0
  defp bar_pct(count, max), do: max(round(count / max * 100), 4)
end
