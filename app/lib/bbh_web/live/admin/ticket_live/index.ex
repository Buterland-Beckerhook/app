defmodule BbhWeb.Admin.TicketLive.Index do
  @moduledoc """
  The Postfach list: tickets of the queues the user works (admins: all), filtered on
  plain columns only. Subjects are decrypted per page; opening a list writes no view log.
  """
  use BbhWeb, :live_view

  alias Bbh.Tickets
  alias Bbh.Tickets.{Queue, Ticket}
  alias BbhWeb.Authz

  # "Offen" is the work nobody has taken yet; "Alle" everything still in work.
  @views [
    {"open", "Offen"},
    {"mine", "Mir zugewiesen"},
    {"overdue", "Überfällig"},
    {"all", "Alle"},
    {"closed", "Erledigt"},
    {"spam", "Spam"}
  ]

  @impl true
  def mount(_params, _session, socket) do
    if connected?(socket), do: Tickets.subscribe()
    scope = socket.assigns.current_scope

    views =
      if Authz.can_delete_ticket?(scope), do: @views ++ [{"deleted", "Gelöscht"}], else: @views

    {:ok,
     assign(socket,
       page_title: "Postfach",
       views: views,
       queue_options: for(key <- Authz.visible_queues(scope), do: {Queue.label(key), key})
     )}
  end

  @impl true
  def handle_params(params, _uri, socket) do
    view =
      if List.keymember?(socket.assigns.views, params["ansicht"], 0),
        do: params["ansicht"],
        else: "open"

    queue =
      if Enum.any?(socket.assigns.queue_options, &(elem(&1, 1) == params["queue"])),
        do: params["queue"]

    page = parse_page(params["seite"])

    {:noreply, socket |> assign(view: view, queue: queue, page: page) |> load()}
  end

  @impl true
  def handle_event("filter", %{"queue" => queue}, socket) do
    {:noreply,
     push_patch(socket, to: list_path(socket.assigns, queue: blank_nil(queue), page: 1))}
  end

  @impl true
  def handle_info({:tickets_changed, _id}, socket), do: {:noreply, load(socket)}

  defp load(socket) do
    %{view: view, queue: queue, page: page, current_scope: scope} = socket.assigns
    result = Tickets.list_tickets(scope, view: view, queue: queue, page: page)
    assign(socket, result: result, counts: Tickets.count_views(scope, queue))
  end

  defp parse_page(value) do
    case Integer.parse(value || "") do
      {n, ""} when n > 0 -> n
      _ -> 1
    end
  end

  defp blank_nil(""), do: nil
  defp blank_nil(value), do: value

  defp list_path(assigns, overrides) do
    params =
      %{
        "ansicht" => Keyword.get(overrides, :view, assigns.view),
        "queue" => Keyword.get(overrides, :queue, assigns.queue),
        "seite" => Keyword.get(overrides, :page, assigns.page)
      }
      |> Enum.reject(fn {k, v} ->
        is_nil(v) or {k, v} in [{"ansicht", "open"}, {"seite", 1}]
      end)

    ~p"/admin/postfach?#{params}"
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.admin flash={@flash} current_scope={@current_scope} active={:tickets}>
      <.header>
        Postfach
        <:subtitle>
          Anfragen aus Kontakt- und Mitgliedsformular.
        </:subtitle>
      </.header>

      <div class="mt-6 flex flex-wrap items-center justify-between gap-3">
        <div role="tablist" class="tabs tabs-box">
          <.link
            :for={{key, label} <- @views}
            patch={list_path(assigns, view: key, page: 1)}
            role="tab"
            class={["tab gap-2", @view == key && "tab-active"]}
          >
            {label}
            <span
              :if={(@counts[key] || 0) > 0}
              class={[
                "badge badge-sm",
                if(key == "overdue", do: "badge-warning", else: "badge-neutral")
              ]}
            >
              {@counts[key]}
            </span>
          </.link>
        </div>

        <form :if={length(@queue_options) > 1} phx-change="filter" id="queue-filter">
          <select name="queue" class="select select-bordered select-sm" aria-label="Postfach">
            <option value="">Alle Postfächer</option>
            <option :for={{label, key} <- @queue_options} value={key} selected={@queue == key}>
              {label}
            </option>
          </select>
        </form>
      </div>

      <p :if={@result.entries == []} class="mt-8 text-base-content/60">Keine Anfragen.</p>

      <.table
        :if={@result.entries != []}
        id="tickets"
        rows={@result.entries}
        row_click={&JS.navigate(~p"/admin/postfach/#{Ticket.reference(&1)}")}
      >
        <:col :let={t} label="Nr.">
          <span class="font-mono text-sm whitespace-nowrap">{Ticket.reference(t)}</span>
        </:col>
        <:col :let={t} label="Betreff">
          <.link navigate={~p"/admin/postfach/#{Ticket.reference(t)}"} class="font-medium">
            {t.subject || "(ohne Betreff)"}
          </.link>
        </:col>
        <:col :let={t} label="Postfach">{Queue.label(t.queue)}</:col>
        <:col :let={t} label="Status">
          <.status_badge kind={:ticket} status={t.status} />
          <span :if={t.follow_up_on} class="ml-1 text-sm whitespace-nowrap">
            {Calendar.strftime(t.follow_up_on, "%d.%m.%Y")}
          </span>
        </:col>
        <:col :let={t} label="Bearbeiter">{(t.assignee && t.assignee.email) || "–"}</:col>
        <:col :let={t} label="Eingang">
          <span class="whitespace-nowrap">{age(t.inserted_at)}</span>
        </:col>
        <:col :let={t} label="Zuletzt">
          <span class="whitespace-nowrap">{age(t.last_activity_at)}</span>
        </:col>
      </.table>

      <nav :if={@result.total_pages > 1} class="mt-4 flex items-center gap-3" aria-label="Seiten">
        <.link :if={@page > 1} patch={list_path(assigns, page: @page - 1)} class="btn btn-sm">
          Zurück
        </.link>
        <span class="text-sm">Seite {@page} von {@result.total_pages}</span>
        <.link
          :if={@page < @result.total_pages}
          patch={list_path(assigns, page: @page + 1)}
          class="btn btn-sm"
        >
          Weiter
        </.link>
      </nav>
    </Layouts.admin>
    """
  end

  @doc false
  def age(%DateTime{} = dt) do
    minutes = DateTime.diff(DateTime.utc_now(), dt, :minute)

    cond do
      minutes < 60 -> "vor #{max(minutes, 1)} Min."
      minutes < 24 * 60 -> "vor #{div(minutes, 60)} Std."
      minutes < 14 * 24 * 60 -> "vor #{div(minutes, 24 * 60)} Tg."
      true -> dt |> DateTime.shift_zone!(Bbh.Time.time_zone()) |> Calendar.strftime("%d.%m.%Y")
    end
  end
end
