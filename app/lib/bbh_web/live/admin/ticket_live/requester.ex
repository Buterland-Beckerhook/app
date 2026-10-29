defmodule BbhWeb.Admin.TicketLive.Requester do
  @moduledoc """
  Admin-only: requests for access and erasure (Art. 15 / 17 GDPR). Finds every ticket
  of an e-mail address across all queues and deletes them — restorable for the purge
  period, or for good at once.

  The address is only ever in the socket, never in the URL (and so never in a log).
  """
  use BbhWeb, :live_view

  alias Bbh.Tickets
  alias Bbh.Tickets.{Queue, Retention, Ticket}
  alias BbhWeb.Authz

  @impl true
  def mount(_params, _session, socket) do
    if Authz.can_delete_ticket?(socket.assigns.current_scope) do
      {:ok,
       assign(socket,
         page_title: "Auskunft & Löschung",
         email: nil,
         tickets: nil,
         form: to_form(%{"email" => ""}, as: "lookup")
       )}
    else
      {:ok,
       socket
       |> put_flash(:error, "Nur für Administratoren.")
       |> push_navigate(to: ~p"/admin/postfach")}
    end
  end

  @impl true
  def handle_event("search", %{"lookup" => %{"email" => email}}, socket) do
    email = String.trim(email)

    if email == "" do
      {:noreply, assign(socket, email: nil, tickets: nil)}
    else
      {:ok, tickets} = Tickets.requester_tickets(socket.assigns.current_scope, email)
      {:noreply, assign(socket, email: email, tickets: tickets)}
    end
  end

  def handle_event("delete_all", %{"purge" => purge}, socket) do
    %{current_scope: scope, email: email} = socket.assigns
    {:ok, count} = Tickets.delete_requester_tickets(scope, email, purge: purge == "true")
    {:ok, tickets} = Tickets.requester_tickets(scope, email)

    message =
      if purge == "true",
        do: "#{count} Anfrage(n) endgültig gelöscht.",
        else: "#{count} Anfrage(n) gelöscht — #{Retention.purge_days()} Tage wiederherstellbar."

    {:noreply, socket |> put_flash(:info, message) |> assign(tickets: tickets)}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.admin flash={@flash} current_scope={@current_scope} active={:tickets}>
      <.header>
        Auskunft & Löschung
        <:subtitle>
          Alle Anfragen einer E-Mail-Adresse in allen Postfächern — für Auskunfts- und
          Löschanträge (Art. 15 und 17 DSGVO).
        </:subtitle>
        <:actions>
          <.button navigate={~p"/admin/postfach"}>Zum Postfach</.button>
        </:actions>
      </.header>

      <.form
        for={@form}
        id="lookup-form"
        phx-submit="search"
        class="mt-6 flex flex-wrap items-end gap-2"
      >
        <div class="min-w-72 grow">
          <.input field={@form[:email]} type="email" label="E-Mail-Adresse" required />
        </div>
        <.button class="btn btn-primary mb-2">Suchen</.button>
      </.form>

      <div :if={@tickets == []} class="mt-6 text-base-content/60">
        Keine Anfragen von {@email}.
      </div>

      <div :if={@tickets not in [nil, []]} class="mt-6">
        <p class="mb-2 text-sm">{length(@tickets)} Anfrage(n) von {@email}:</p>

        <.table id="requester-tickets" rows={@tickets}>
          <:col :let={t} label="Nr.">
            <.link
              navigate={~p"/admin/postfach/#{Ticket.reference(t)}"}
              class="link font-mono text-sm"
            >
              {Ticket.reference(t)}
            </.link>
          </:col>
          <:col :let={t} label="Betreff">{t.subject}</:col>
          <:col :let={t} label="Postfach">{Queue.label(t.queue)}</:col>
          <:col :let={t} label="Status">
            <.status_badge kind={:ticket} status={t.status} />
            <span :if={t.deleted_at} class="badge badge-error badge-sm ml-1">gelöscht</span>
          </:col>
          <:col :let={t} label="Eingang">
            {t.inserted_at
            |> DateTime.shift_zone!(Bbh.Time.time_zone())
            |> Calendar.strftime("%d.%m.%Y")}
          </:col>
        </.table>

        <div class="mt-6 flex flex-wrap gap-2">
          <.button
            phx-click={JS.push("delete_all", value: %{purge: "false"})}
            data-confirm={"Alle Anfragen von #{@email} löschen? Sie lassen sich #{Retention.purge_days()} Tage lang wiederherstellen."}
            class="btn btn-error btn-soft"
          >
            Alle löschen
          </.button>
          <.button
            phx-click={JS.push("delete_all", value: %{purge: "true"})}
            data-confirm={"Alle Anfragen von #{@email} SOFORT und ENDGÜLTIG löschen, samt Nachrichten und Anhängen? Das lässt sich nicht rückgängig machen."}
            class="btn btn-error"
          >
            Sofort endgültig löschen
          </.button>
        </div>
        <p class="mt-2 text-sm text-base-content/60">
          „Sofort endgültig“ ist für ausdrückliche Löschanträge. Kopien in den Backups
          verschwinden mit deren Aufbewahrungsfrist.
        </p>
      </div>
    </Layouts.admin>
    """
  end
end
