defmodule BbhWeb.Admin.TicketLive.Show do
  @moduledoc """
  One Postfach ticket: the thread (requests, replies, notes, system notes), taking and
  assigning it, status and follow-up date, notes, queue moves, spam, the structured
  membership application, other tickets of the same sender and the history.

  Opening it writes a `viewed` event (throttled); changes elsewhere update it live.
  """
  use BbhWeb, :live_view

  alias Bbh.Tickets
  alias Bbh.Tickets.{Queue, Ticket}
  alias BbhWeb.Authz

  @impl true
  def mount(%{"ref" => ref}, _session, socket) do
    scope = socket.assigns.current_scope

    case Tickets.get_ticket(scope, ref) do
      {:ok, ticket} ->
        if connected?(socket) do
          Tickets.subscribe()
          Tickets.record_view(scope, ticket)
        end

        {:ok,
         socket
         |> assign(
           page_title: Ticket.reference(ticket),
           note_form: note_form(),
           reply_form: reply_form(),
           replies_enabled: Tickets.replies_enabled?()
         )
         |> assign_ticket(ticket)}

      {:error, :not_found} ->
        {:ok,
         socket
         |> put_flash(:error, "Anfrage nicht gefunden.")
         |> push_navigate(to: ~p"/admin/postfach")}
    end
  end

  defp assign_ticket(socket, ticket) do
    scope = socket.assigns.current_scope

    assign(socket,
      ticket: ticket,
      # What the status select shows; differs from the ticket's status only while a
      # follow-up waits for its date.
      status_choice: ticket.status,
      assignees: Tickets.assignable_users(ticket),
      related: Tickets.related_tickets(scope, ticket),
      events: Tickets.list_events(ticket),
      can_delete: Authz.can_delete_ticket?(scope),
      deleted: not is_nil(ticket.deleted_at)
    )
  end

  defp reload(socket) do
    case Tickets.get_ticket(socket.assigns.current_scope, socket.assigns.ticket.number) do
      {:ok, ticket} ->
        assign_ticket(socket, ticket)

      {:error, :not_found} ->
        socket
        |> put_flash(:info, "Die Anfrage liegt jetzt in einem anderen Postfach.")
        |> push_navigate(to: ~p"/admin/postfach")
    end
  end

  defp note_form, do: to_form(%{"body" => ""}, as: "note")
  defp reply_form, do: to_form(%{"body" => "", "status" => "waiting"}, as: "reply")

  @reply_statuses [
    {"Danach: Wartet auf Antwort", "waiting"},
    {"Danach: In Bearbeitung", "open"},
    {"Danach: Erledigt", "closed"}
  ]

  @impl true
  def handle_event("take", _params, socket),
    do: socket |> run(&Tickets.take(&1, &2), "Übernommen.") |> noreply()

  def handle_event("assign", %{"assignee_id" => id}, socket),
    do: socket |> run(&Tickets.assign(&1, &2, id), "Zugewiesen.") |> noreply()

  # Applies on selection, like assignee and queue. A follow-up first needs its date: the
  # date field appears, and the change is saved once a date is picked.
  def handle_event("status", %{"status" => status} = params, socket) do
    date = params["follow_up_on"]
    ticket = socket.assigns.ticket

    cond do
      status == "follow_up" and date in [nil, ""] ->
        {:noreply, assign(socket, status_choice: "follow_up")}

      status == ticket.status and status != "follow_up" ->
        {:noreply, socket}

      true ->
        socket
        |> run(&Tickets.set_status(&1, &2, status, date), "Status geändert.")
        |> noreply()
    end
  end

  def handle_event("unspam", _params, socket),
    do:
      socket |> run(&Tickets.unmark_spam(&1, &2), "Kein Spam – zurück im Postfach.") |> noreply()

  def handle_event("reply", %{"reply" => %{"body" => body, "status" => status}}, socket) do
    %{current_scope: scope, ticket: ticket} = socket.assigns

    case Tickets.reply(scope, ticket, body, status) do
      {:ok, _} ->
        {:noreply,
         socket
         |> put_flash(:info, "Antwort wird gesendet.")
         |> assign(reply_form: reply_form())
         |> reload()}

      {:error, :empty} ->
        {:noreply, put_flash(socket, :error, "Die Antwort ist leer.")}

      {:error, :replies_disabled} ->
        {:noreply, put_flash(socket, :error, "Antworten sind noch nicht eingerichtet.")}

      {:error, _} ->
        {:noreply, put_flash(socket, :error, "Antwort nicht gesendet.")}
    end
  end

  def handle_event("note", %{"note" => %{"body" => body}}, socket) do
    case Tickets.add_note(socket.assigns.current_scope, socket.assigns.ticket, body) do
      {:ok, _} -> {:noreply, socket |> assign(note_form: note_form()) |> reload()}
      {:error, :empty} -> {:noreply, put_flash(socket, :error, "Die Notiz ist leer.")}
      {:error, _} -> {:noreply, put_flash(socket, :error, "Notiz nicht gespeichert.")}
    end
  end

  def handle_event("move", %{"queue" => queue}, socket),
    do:
      socket
      |> run(&Tickets.move_queue(&1, &2, queue), "Verschoben nach #{Queue.label(queue)}.")
      |> noreply()

  def handle_event("spam", _params, socket),
    do: socket |> run(&Tickets.mark_spam(&1, &2), "Als Spam markiert.") |> noreply()

  def handle_event("delete", _params, socket),
    do: socket |> run(&Tickets.delete_ticket(&1, &2), "Gelöscht.") |> noreply()

  def handle_event("restore", _params, socket),
    do: socket |> run(&Tickets.restore_ticket(&1, &2), "Wiederhergestellt.") |> noreply()

  def handle_event("member_number", %{"member_number" => number}, socket) do
    socket
    |> run(&Tickets.set_member_number(&1, &2, number), "Mitgliedsnummer gespeichert.")
    |> noreply()
  end

  @impl true
  def handle_info({:tickets_changed, id}, socket) do
    if id == socket.assigns.ticket.id, do: {:noreply, reload(socket)}, else: {:noreply, socket}
  end

  defp run(socket, fun, success) do
    case fun.(socket.assigns.current_scope, socket.assigns.ticket) do
      {:ok, _} ->
        socket |> put_flash(:info, success) |> reload()

      {:error, %Ecto.Changeset{} = changeset} ->
        message =
          changeset.errors |> Enum.map(fn {_, {msg, _}} -> msg end) |> Enum.join(" ")

        put_flash(socket, :error, message)

      {:error, :invalid_assignee} ->
        put_flash(socket, :error, "Diese Person hat keinen Zugriff auf das Postfach.")

      {:error, _} ->
        put_flash(socket, :error, "Das hat nicht geklappt.")
    end
  end

  defp noreply(socket), do: {:noreply, socket}

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.admin flash={@flash} current_scope={@current_scope} active={:tickets}>
      <.header>
        <span class="font-mono text-base text-base-content/60">{Ticket.reference(@ticket)}</span>
        <span class="block">{@ticket.subject || "(ohne Betreff)"}</span>
        <:subtitle>
          {Queue.label(@ticket.queue)} · eingegangen {local(@ticket.inserted_at)}
          <span :if={@deleted} class="badge badge-error ml-2">Gelöscht</span>
        </:subtitle>
        <:actions>
          <.button navigate={~p"/admin/postfach"}>Zur Liste</.button>
        </:actions>
      </.header>

      <div class="mt-6 grid gap-6 lg:grid-cols-[1fr_20rem]">
        <div class="min-w-0 space-y-6">
          <.membership :if={@ticket.kind == "membership"} payload={@ticket.payload || %{}} />

          <section aria-label="Verlauf" class="space-y-3">
            <article
              :for={m <- @ticket.messages}
              id={"message-#{m.id}"}
              class={["rounded-box border p-4", message_class(m.direction)]}
            >
              <header class="mb-2 flex flex-wrap items-baseline justify-between gap-2 text-sm">
                <span class="font-semibold">{message_label(m, @ticket)}</span>
                <time class="text-base-content/60">{local(m.inserted_at)}</time>
              </header>
              <div class="whitespace-pre-wrap break-words">{m.body}</div>
              <ul :if={m.attachments != []} class="mt-3 space-y-1 text-sm">
                <li :for={a <- m.attachments} class="flex items-center gap-2">
                  <.icon name="hero-paper-clip" class="size-4" />
                  {a.filename} <span class="text-base-content/60">({kb(a.size)})</span>
                </li>
              </ul>
            </article>
          </section>

          <.form
            :if={can_reply?(@ticket, @deleted, @replies_enabled)}
            for={@reply_form}
            id="reply-form"
            phx-submit="reply"
            class="rounded-box border border-primary/40 p-4"
          >
            <.input
              field={@reply_form[:body]}
              type="textarea"
              label={"Antwort an #{@ticket.requester_email}"}
              rows="8"
            />
            <p class="-mt-1 mb-3 text-xs text-base-content/60">
              Geht als E-Mail von {Queue.reply_address(@ticket.queue)} mit dem Betreff
              „{Bbh.Tickets.ReplyMail.subject(@ticket)}“. Gruß und Vereinsangaben werden
              angehängt.
            </p>
            <div class="flex flex-wrap items-end gap-2">
              <.input field={@reply_form[:status]} type="select" options={reply_statuses()} />
              <.button
                class="btn btn-primary mb-2"
                phx-disable-with="Sende…"
                data-confirm="Antwort jetzt an den Absender senden?"
              >
                Antwort senden
              </.button>
            </div>
          </.form>
          <p
            :if={not @replies_enabled and not @deleted and @ticket.requester_email}
            class="text-sm text-base-content/60"
          >
            Antworten aus dem Postfach sind noch nicht eingerichtet (TICKET_SMTP_USERNAME).
          </p>

          <.form :if={not @deleted} for={@note_form} id="note-form" phx-submit="note">
            <.input
              field={@note_form[:body]}
              type="textarea"
              label="Interne Notiz"
              rows="4"
              placeholder="Nur im Postfach sichtbar, geht nicht an den Absender."
            />
            <.button phx-disable-with="Speichere…">Notiz speichern</.button>
          </.form>
        </div>

        <aside class="space-y-6">
          <section class="rounded-box bg-base-200 p-4 space-y-4">
            <div>
              <h2 class="text-sm font-semibold">Absender</h2>
              <p>{@ticket.requester_name || "–"}</p>
              <p class="break-all text-sm">{@ticket.requester_email}</p>
            </div>

            <div :if={not @deleted} class="space-y-2">
              <h2 class="text-sm font-semibold">Bearbeitung</h2>
              <.button
                :if={@ticket.assignee_id != @current_scope.user.id}
                phx-click="take"
                class="btn btn-primary btn-sm w-full"
              >
                Übernehmen
              </.button>
              <form phx-change="assign" id="assign-form">
                <label class="text-sm" for="assignee_id">Zugewiesen an</label>
                <select
                  id="assignee_id"
                  name="assignee_id"
                  class="select select-bordered select-sm w-full"
                >
                  <option value="">– niemand –</option>
                  <option
                    :for={u <- @assignees}
                    value={u.id}
                    selected={u.id == @ticket.assignee_id}
                  >
                    {u.email}
                  </option>
                </select>
              </form>
            </div>

            <div :if={not @deleted}>
              <h2 class="text-sm font-semibold">Status</h2>
              <p class="mb-2"><.status_badge kind={:ticket} status={@ticket.status} /></p>
              <form phx-change="status" id="status-form" class="space-y-2">
                <label class="sr-only" for="status-select">Status ändern</label>
                <select
                  id="status-select"
                  name="status"
                  class="select select-bordered select-sm w-full"
                >
                  <%!-- "Neu" and "Spam" are never set by hand, but the select shows them. --%>
                  <option
                    :if={@status_choice not in Enum.map(Ticket.status_options(), &elem(&1, 1))}
                    value={@status_choice}
                    selected
                    disabled
                  >
                    {Ticket.status_label(@status_choice)}
                  </option>
                  <option
                    :for={{label, value} <- Ticket.status_options()}
                    value={value}
                    selected={value == @status_choice}
                  >
                    {label}
                  </option>
                </select>
                <div :if={@status_choice == "follow_up"}>
                  <label class="text-sm" for="follow_up_on">Wiedervorlage am</label>
                  <input
                    type="date"
                    id="follow_up_on"
                    name="follow_up_on"
                    value={@ticket.follow_up_on && Date.to_iso8601(@ticket.follow_up_on)}
                    class="input input-bordered input-sm w-full"
                  />
                </div>
              </form>
            </div>

            <form :if={not @deleted} phx-change="move" id="move-form">
              <label class="text-sm font-semibold" for="move-queue">Postfach</label>
              <select id="move-queue" name="queue" class="select select-bordered select-sm w-full">
                <option
                  :for={{label, key} <- Queue.options()}
                  value={key}
                  selected={key == @ticket.queue}
                >
                  {label}
                </option>
              </select>
            </form>

            <div class="flex flex-wrap gap-2 pt-2">
              <.button
                :if={not @deleted and @ticket.status == "spam"}
                phx-click="unspam"
                class="btn btn-sm"
              >
                Kein Spam
              </.button>
              <.button
                :if={not @deleted and @ticket.status != "spam"}
                phx-click="spam"
                data-confirm="Als Spam markieren?"
                class="btn btn-sm btn-ghost"
              >
                Spam
              </.button>
              <.button
                :if={@can_delete and not @deleted}
                phx-click="delete"
                data-confirm="Anfrage löschen? Sie wird nach Ablauf der Frist endgültig entfernt."
                class="btn btn-sm btn-error btn-soft"
              >
                Löschen
              </.button>
              <.button :if={@can_delete and @deleted} phx-click="restore" class="btn btn-sm">
                Wiederherstellen
              </.button>
            </div>
          </section>

          <section
            :if={@ticket.kind == "membership" and not @deleted}
            class="rounded-box bg-base-200 p-4"
          >
            <form phx-submit="member_number" id="member-number-form" class="space-y-2">
              <label class="text-sm font-semibold" for="member_number">Mitgliedsnummer</label>
              <input
                id="member_number"
                name="member_number"
                value={(@ticket.payload || %{})["member_number"]}
                class="input input-bordered input-sm w-full"
              />
              <p class="text-xs text-base-content/60">Zugleich die Mandatsreferenz.</p>
              <.button class="btn btn-sm w-full">Speichern</.button>
            </form>
            <a
              href={~p"/admin/postfach/#{Ticket.reference(@ticket)}/antrag.pdf"}
              class="btn btn-sm btn-primary mt-3 w-full"
              download
            >
              <.icon name="hero-arrow-down-tray" class="size-4" /> PDF herunterladen
            </a>
          </section>

          <section :if={@related != []} class="rounded-box bg-base-200 p-4">
            <h2 class="text-sm font-semibold">Weitere Anfragen dieses Absenders</h2>
            <ul class="mt-2 space-y-1 text-sm">
              <li :for={t <- @related}>
                <.link navigate={~p"/admin/postfach/#{Ticket.reference(t)}"} class="link">
                  {Ticket.reference(t)}
                </.link>
                {t.subject}
              </li>
            </ul>
          </section>

          <details class="rounded-box bg-base-200 p-4" id="history">
            <summary class="cursor-pointer text-sm font-semibold">Verlauf</summary>
            <ul class="mt-2 space-y-1 text-sm">
              <li :for={e <- @events}>
                <span class="text-base-content/60">{local(e.inserted_at)}</span>
                {event_label(e)}
                <span :if={e.user} class="text-base-content/60">– {e.user.email}</span>
              </li>
            </ul>
          </details>
        </aside>
      </div>
    </Layouts.admin>
    """
  end

  attr :payload, :map, required: true

  defp membership(assigns) do
    ~H"""
    <section id="membership" class="rounded-box border border-base-300 p-4">
      <h2 class="font-semibold">Aufnahmeantrag</h2>
      <div :if={@payload["flags"] not in [nil, []]} class="alert alert-warning mt-3 text-sm">
        <div>
          <p class="font-semibold">Hinweise (bitte prüfen)</p>
          <p :for={flag <- @payload["flags"]}>{flag}</p>
        </div>
      </div>
      <dl class="mt-3 grid grid-cols-[auto_1fr] gap-x-4 gap-y-1 text-sm">
        <.row label="Name">{@payload["vorname"]} {@payload["nachname"]}</.row>
        <.row label="Anschrift">{@payload["strasse"]}, {@payload["plz"]} {@payload["ort"]}</.row>
        <.row label="Geburtsdatum">{@payload["geburtsdatum"]}</.row>
        <.row label="E-Mail">{@payload["email"]}</.row>
        <.row :if={@payload["children"] not in [nil, []]} label="Kinder">
          <span :for={c <- @payload["children"]} class="block">
            {c["vorname"]} ({c["geburtsdatum"]})
          </span>
        </.row>
        <.row label="Kontoinhaber">{@payload["kontoinhaber"]}</.row>
        <.row label="IBAN"><span class="font-mono">{@payload["iban"]}</span></.row>
        <.row label="BIC">{@payload["bic"]}</.row>
        <.row label="Kreditinstitut">{@payload["kreditinstitut"]}</.row>
        <.row label="SEPA-Mandat">{if @payload["sepa"], do: "erteilt", else: "nein"}</.row>
        <.row :if={@payload["submitted_at"]} label="Übermittelt">
          {local_iso(@payload["submitted_at"])} · IP {@payload["client_ip"]} · Formular {@payload[
            "form_version"
          ]}
        </.row>
      </dl>
    </section>
    """
  end

  attr :label, :string, required: true
  slot :inner_block, required: true

  defp row(assigns) do
    ~H"""
    <dt class="text-base-content/60">{@label}</dt>
    <dd>{render_slot(@inner_block)}</dd>
    """
  end

  defp message_class("in"), do: "border-base-300"
  defp message_class("out"), do: "border-primary/40 bg-primary/5"
  defp message_class("note"), do: "border-warning/40 bg-warning/10"
  defp message_class(_system), do: "border-dashed border-base-300 text-sm text-base-content/70"

  defp message_label(%{direction: "in"}, %{kind: "contact"}), do: "Kontaktformular"
  defp message_label(%{direction: "in"}, %{kind: "membership"}), do: "Mitgliedsantrag"
  defp message_label(%{direction: "in", from: from}, _), do: "E-Mail von #{from}"

  defp message_label(%{direction: "out", author: author} = m, _),
    do: "Antwort von #{author && author.email}#{if is_nil(m.sent_at), do: " · wird gesendet …"}"

  defp message_label(%{direction: "note", author: author}, _),
    do: "Notiz von #{author && author.email}"

  defp message_label(_message, _ticket), do: "System"

  @event_labels %{
    "created" => "eingegangen",
    "viewed" => "angesehen",
    "assigned" => "Zuweisung geändert",
    "status_changed" => "Status geändert",
    "queue_changed" => "Postfach gewechselt",
    "replied" => "beantwortet",
    "noted" => "Notiz",
    "received" => "Antwort des Absenders eingegangen",
    "attachment_downloaded" => "Anhang heruntergeladen",
    "pdf_exported" => "PDF heruntergeladen",
    "marked_spam" => "als Spam markiert",
    "unmarked_spam" => "Spam-Markierung aufgehoben",
    "deleted" => "gelöscht",
    "restored" => "wiederhergestellt",
    "server_copy_removed" => "Serverkopie entfernt",
    "member_number_set" => "Mitgliedsnummer gesetzt"
  }

  defp event_label(%{action: "status_changed", meta: %{"to" => to}}),
    do: "Status: #{Ticket.status_label(to)}"

  defp event_label(%{action: "queue_changed", meta: %{"to" => to}}),
    do: "Postfach: #{Queue.label(to)}"

  defp event_label(%{action: action}), do: Map.get(@event_labels, action, action)

  defp local(dt),
    do: dt |> DateTime.shift_zone!(Bbh.Time.time_zone()) |> BbhWeb.Format.de_short_datetime()

  defp local_iso(iso) do
    case DateTime.from_iso8601(iso) do
      {:ok, dt, _} -> local(dt)
      _ -> iso
    end
  end

  defp reply_statuses, do: @reply_statuses

  defp can_reply?(ticket, deleted, enabled),
    do:
      enabled and not deleted and ticket.status != "spam" and
        ticket.requester_email not in [nil, ""]

  defp kb(size) when size < 1024, do: "#{size} B"
  defp kb(size), do: "#{Float.round(size / 1024, 1)} KB"
end
