defmodule BbhWeb.Admin.DashboardLive do
  @moduledoc """
  The admin start page. Decides what the user may see; the figures come from
  `Bbh.Dashboard`, the markup from `BbhWeb.Admin.DashboardLive.Components`.
  """
  use BbhWeb, :live_view

  import BbhWeb.Admin.DashboardLive.Components

  @ranges [7, 30, 90]
  @default_range 30

  @impl true
  def mount(_params, _session, socket) do
    scope = socket.assigns.current_scope
    # The dashboard is open to a plain magic-link session (it is where Termine editors
    # land), so what it shows from the strong-auth areas — ticket subjects, visitor
    # analytics — needs the strong session those areas do. Every staff member then sees
    # the basic access figures; referrers, search terms, iCal and push stay with admins.
    # Without any access (e.g. after leaving the board) the page is only a notice.
    no_access = Bbh.Authz.no_access?(scope)
    strong? = Bbh.Accounts.User.strong_auth?(scope.user)
    show_analytics = strong? and not no_access
    full_analytics = show_analytics and Bbh.Authz.admin?(scope)

    tickets =
      if strong? and not no_access and Bbh.Authz.can_access_tickets?(scope),
        do: Bbh.Dashboard.tickets(scope)

    socket =
      socket
      |> assign(
        page_title: "Übersicht",
        no_access: no_access,
        show_analytics: show_analytics,
        full_analytics: full_analytics,
        range_days: @default_range,
        ranges: @ranges,
        tickets: tickets,
        # Admins only: image and commit are of no use to editors.
        build_info: if(Bbh.Authz.admin?(scope), do: Bbh.BuildInfo.get())
      )
      # Off the connected mount, so the page shell renders without blocking on the DB.
      |> assign_async(:stats, fn -> {:ok, %{stats: Bbh.Dashboard.content_counts()}} end)

    {:ok, if(show_analytics, do: load_analytics(socket), else: socket)}
  end

  @impl true
  def handle_event("set_range", %{"days" => days}, socket) do
    if socket.assigns.show_analytics do
      {:noreply, socket |> assign(range_days: parse_range(days)) |> load_analytics()}
    else
      {:noreply, socket}
    end
  end

  # Anything but an offered range — including a hand-crafted non-number — is the default.
  defp parse_range(days) do
    case Integer.parse(to_string(days)) do
      {n, ""} when n in @ranges -> n
      _ -> @default_range
    end
  end

  defp load_analytics(socket) do
    %{range_days: days, full_analytics: full?} = socket.assigns

    assign_async(socket, :analytics, fn ->
      {:ok, %{analytics: Bbh.Dashboard.analytics(days, full?)}}
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

      <div :if={@no_access} id="no-access" role="status" class="alert mt-6 max-w-2xl items-start">
        <.icon name="hero-information-circle" class="size-5 shrink-0" />
        <div class="space-y-2">
          <p>
            Du hast im Verwaltungsbereich zurzeit keine Berechtigungen.
          </p>
          <p>Wenn du Fragen hast oder meinst, dass das nicht stimmt, melde dich bitte bei uns:</p>
          <p><.link href={~p"/kontakt"} class="link">Zum Kontaktformular</.link></p>
        </div>
      </div>

      <p
        :if={@current_scope.user.delete_on}
        id="delete-on-notice"
        class="mt-4 max-w-2xl text-sm text-base-content/70"
      >
        Dein Zugang wird am {de_date(@current_scope.user.delete_on)} gelöscht.
      </p>

      <.tickets_widget :if={@tickets} tickets={@tickets} />

      <.async_result :let={stats} :if={!@no_access} assign={@stats}>
        <:loading>
          <div class="mt-6 grid grid-cols-2 gap-4 md:grid-cols-4">
            <div :for={_ <- 1..4} class="h-20 animate-pulse rounded-box bg-base-200"></div>
          </div>
        </:loading>
        <:failed :let={_reason}>
          <p class="mt-6 text-error">Statistik konnte nicht geladen werden.</p>
        </:failed>

        <.stat_cards stats={stats} user={@current_scope.user} />
      </.async_result>

      <section :if={@show_analytics} class="mt-10">
        <div class="flex flex-wrap items-center justify-between gap-2">
          <h2 class="text-lg font-semibold">Zugriffe</h2>
          <div class="join">
            <button
              :for={d <- @ranges}
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

          <.analytics_tiles a={a} full={@full_analytics} />
          <.views_chart by_day={a.by_day} />

          <div class="mt-6 grid gap-6 md:grid-cols-2">
            <.top_list title="Top-Seiten" rows={a.top_pages} key={:path} empty="Noch keine Aufrufe." />
            <.top_articles rows={a.top_articles} />
            <.top_list
              :if={@full_analytics}
              title="Top-Verweise"
              rows={a.top_referrers}
              key={:host}
              empty="Keine externen Verweise."
            />
            <.top_searches :if={@full_analytics} rows={a.top_searches} />
          </div>

          <.ical_clients :if={@full_analytics} rows={a.ical_clients} />
        </.async_result>
      </section>

      <.build_info :if={@build_info} info={@build_info} />
    </Layouts.admin>
    """
  end
end
