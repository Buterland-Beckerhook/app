defmodule BbhWeb.Admin.DashboardLive.Components do
  @moduledoc """
  The pieces of the admin start page (`BbhWeb.Admin.DashboardLive`): the Postfach
  widget, the content stat cards and the visitor analytics. Pure rendering — the data
  comes from `Bbh.Dashboard`, the access decisions from the LiveView.
  """
  use BbhWeb, :html

  alias Bbh.Tickets.Ticket

  attr :tickets, :map, required: true, doc: "`Bbh.Dashboard.tickets/1`"

  def tickets_widget(assigns) do
    ~H"""
    <section id="tickets-widget" class="mt-6 rounded-box border border-base-300 p-4">
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
          <.link navigate={~p"/admin/postfach/#{Ticket.reference(t)}"} class="link font-mono">
            {Ticket.reference(t)}
          </.link>
          <span>{t.subject}</span>
          <.status_badge kind={:ticket} status={t.status} />
        </li>
      </ul>
    </section>
    """
  end

  attr :stats, :map, required: true, doc: "`Bbh.Dashboard.content_counts/0`"
  attr :user, :any, required: true

  # One card per area the user may open.
  def stat_cards(assigns) do
    ~H"""
    <div class="mt-6 grid grid-cols-2 gap-4 md:grid-cols-4">
      <.stat_card
        :if={Bbh.Authz.can_access_section?(@user, :articles)}
        label="Artikel"
        value={total(@stats.articles)}
        breakdown={status_breakdown(@stats.articles)}
        navigate={~p"/admin/artikel"}
      />
      <.stat_card
        :if={Bbh.Authz.can_access_section?(@user, :events)}
        label="Termine"
        value={total(@stats.events)}
        breakdown={status_breakdown(@stats.events)}
        navigate={~p"/admin/termine"}
      />
      <.stat_card
        :if={Bbh.Authz.can_access_section?(@user, :people)}
        label="Personen"
        value={@stats.people}
        navigate={~p"/admin/personen"}
      />
      <.stat_card
        :if={Bbh.Authz.can_access_section?(@user, :pages)}
        label="Seiten"
        value={total(@stats.pages)}
        breakdown={status_breakdown(@stats.pages)}
        navigate={~p"/admin/seiten"}
      />
    </div>
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

  attr :a, :map, required: true, doc: "`Bbh.Dashboard.analytics/2`"
  attr :full, :boolean, required: true, doc: "the admin-only figures are loaded"

  # The headline numbers above the chart.
  def analytics_tiles(assigns) do
    ~H"""
    <div class="mt-4 grid grid-cols-2 gap-4 md:max-w-sm">
      <.tile value={@a.summary.views} label="Seitenaufrufe" />
      <.tile value={@a.summary.visits} label="Besuche" title="Summe der täglichen Besucher" />
      <.tile
        :if={@full}
        value={@a.ical.fetches}
        label="iCal-Abrufe"
        title="Abrufe des Termin-Abo-Feeds (.ics)"
      />
      <.tile
        :if={@full}
        value={@a.ical.subscribers}
        label="iCal-Abos"
        title="Verschiedene Kalender-Clients am aktivsten Tag"
      />
      <.tile
        :if={@full}
        value={@a.push_subscriptions}
        label="Push-Abos"
        title="Aktive Push-Benachrichtigungs-Abos"
      />
    </div>
    """
  end

  attr :value, :integer, required: true
  attr :label, :string, required: true
  attr :title, :string, default: nil

  defp tile(assigns) do
    ~H"""
    <div class="rounded-box border border-base-300 bg-base-200 p-4">
      <div class="text-3xl font-semibold text-primary">{@value}</div>
      <div class="text-sm text-base-content/70" title={@title}>{@label}</div>
    </div>
    """
  end

  attr :by_day, :list, required: true, doc: "`[%{day:, count:}]`, oldest first"

  def views_chart(assigns) do
    assigns =
      assign(assigns,
        peak: day_max(assigns.by_day),
        top: assigns.by_day |> day_max() |> nice_ceil()
      )

    ~H"""
    <div class="mt-6 rounded-box border border-base-300 bg-base-200 p-4">
      <div class="mb-2 flex items-baseline justify-between gap-2 text-sm text-base-content/70">
        <span>Aufrufe pro Tag</span>
        <span :if={@peak > 0} class="text-xs tabular-nums">
          Ø {day_avg(@by_day)} · Spitze {@peak}
        </span>
      </div>
      <div class="flex gap-2">
        <div class="flex h-32 w-8 shrink-0 flex-col justify-between text-right text-[10px] text-base-content/50 tabular-nums">
          <span>{@top}</span>
          <span>{round(@top / 2)}</span>
          <span>0</span>
        </div>
        <div class="relative flex h-32 flex-1 items-end gap-px">
          <div class="pointer-events-none absolute inset-x-0 top-1/2 border-t border-base-content/10">
          </div>
          <div
            :for={point <- @by_day}
            class="flex-1 rounded-t bg-primary/70 hover:bg-primary"
            style={"height: #{bar_pct(point.count, @top)}%"}
            title={"#{Calendar.strftime(point.day, "%d.%m.")}: #{point.count}"}
          >
          </div>
        </div>
      </div>
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

  attr :title, :string, required: true
  attr :rows, :list, required: true
  attr :key, :atom, required: true
  attr :empty, :string, required: true

  def top_list(assigns) do
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

  # Articles by page views, linked to their public page.
  def top_articles(assigns) do
    ~H"""
    <div id="top-articles" class="rounded-box border border-base-300 bg-base-200 p-4">
      <div class="mb-2 text-sm font-medium">Top-Artikel</div>
      <p :if={@rows == []} class="text-sm text-base-content/60">
        Keine Artikelaufrufe im Zeitraum.
      </p>
      <ul class="space-y-1">
        <li :for={row <- @rows} class="flex items-center justify-between gap-3 text-sm">
          <a
            href={row.path}
            target="_blank"
            class="truncate text-base-content/80 hover:underline"
          >
            {row.title}
          </a>
          <span class="shrink-0 font-medium tabular-nums">{row.views}</span>
        </li>
      </ul>
    </div>
    """
  end

  attr :rows, :list, required: true

  # Site-search terms. A term that never found anything is flagged — that is content
  # visitors look for and don't get.
  def top_searches(assigns) do
    ~H"""
    <div id="top-searches" class="rounded-box border border-base-300 bg-base-200 p-4">
      <div class="mb-2 text-sm font-medium">Top-Suchbegriffe</div>
      <p :if={@rows == []} class="text-sm text-base-content/60">Keine Suchen im Zeitraum.</p>
      <ul class="space-y-1">
        <li :for={row <- @rows} class="flex items-center justify-between gap-3 text-sm">
          <span class="truncate text-base-content/80">
            {row.term}
            <span
              :if={row.no_results > 0}
              class="text-xs text-warning"
              title={"#{row.no_results} von #{row.searches} Suchen ohne Treffer"}
            >
              {no_results_label(row)}
            </span>
          </span>
          <span class="shrink-0 font-medium tabular-nums">{row.searches}</span>
        </li>
      </ul>
    </div>
    """
  end

  defp no_results_label(%{no_results: n, searches: n}), do: "· ohne Treffer"
  defp no_results_label(_row), do: "· teils ohne Treffer"

  attr :rows, :list, required: true

  # iCal subscriptions per calendar-client family. Only the family is known — the
  # feed is anonymous and the visitor hash rotates daily, so there are no per-person IDs.
  def ical_clients(assigns) do
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

  attr :info, Bbh.BuildInfo, required: true

  # The running build in full (admins only): what to name in a bug report or when
  # comparing Beta with Prod. `Bbh.BuildInfo` says where each value comes from.
  def build_info(assigns) do
    info = assigns.info
    runtime = Bbh.BuildInfo.runtime_versions()
    built_at = Bbh.BuildInfo.built_at_local(info)

    assigns =
      assign(assigns,
        built?: Bbh.BuildInfo.built?(info),
        release_url: Bbh.BuildInfo.release_url(info),
        version: info.version || "noch kein Release",
        commit: Bbh.BuildInfo.short_commit(info),
        commit_url: Bbh.BuildInfo.commit_url(info),
        built_at: if(built_at, do: de_short_datetime(built_at), else: "–"),
        started_at: de_short_datetime(Bbh.BuildInfo.started_at()),
        runtime: "Elixir #{runtime.elixir} · OTP #{runtime.otp}"
      )

    ~H"""
    <section id="build-info" class="mt-10">
      <h2 class="text-lg font-semibold">System</h2>
      <div class="mt-4 rounded-box border border-base-300 bg-base-200 p-4">
        <p :if={!@built?} class="mb-3 text-sm text-base-content/70">
          Entwicklungsumgebung – keine Build-Informationen.
        </p>
        <dl class="grid grid-cols-[auto_1fr] gap-x-6 gap-y-1.5 text-sm">
          <%= if @built? do %>
            <dt class="text-base-content/60">Version</dt>
            <dd id="build-version" class="break-all font-mono">
              <a :if={@release_url} href={@release_url} class="link link-hover" target="_blank">
                {@version}
              </a>
              <span :if={!@release_url}>{@version}</span>
            </dd>

            <dt class="text-base-content/60">Image</dt>
            <dd id="build-image" class="break-all font-mono">{@info.image || "–"}</dd>

            <dt class="text-base-content/60">Build-Tag</dt>
            <dd id="build-tag" class="break-all font-mono">{@info.build_tag || "–"}</dd>

            <dt class="text-base-content/60">Commit</dt>
            <dd id="build-commit" class="break-all font-mono">
              <a href={@commit_url} class="link link-hover" target="_blank">{@commit}</a>
              <span :if={@info.ref} class="font-sans text-base-content/60">({@info.ref})</span>
            </dd>

            <dt class="text-base-content/60">Gebaut</dt>
            <dd id="build-time">
              {@built_at}
              <a :if={@info.run_url} href={@info.run_url} class="link link-hover" target="_blank">
                (Workflow-Lauf)
              </a>
            </dd>
          <% end %>

          <dt class="text-base-content/60">Gestartet</dt>
          <dd id="build-started">{@started_at}</dd>

          <dt class="text-base-content/60">Laufzeit</dt>
          <dd class="font-mono">{@runtime}</dd>
        </dl>
      </div>
    </section>
    """
  end
end
