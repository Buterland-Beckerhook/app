defmodule BbhWeb.Admin.TicketLive.Show do
  @moduledoc """
  One Postfach ticket: the thread (requests, replies, notes, system notes), taking and
  assigning it, status and follow-up date, notes, queue moves, spam, the structured
  membership application, other tickets of the same sender and the history.

  Opening it writes a `viewed` event (throttled); changes elsewhere update it live.

  The assign, status and move forms save on change, so they opt out of LiveView's form
  recovery: after a reconnect it would resend what the old page showed, as if clicked.
  """
  use BbhWeb, :live_view

  import BbhWeb.Admin.TicketLive.ShowComponents

  alias Bbh.Tickets
  alias Bbh.Tickets.{Queue, Ticket}
  alias Bbh.Authz

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
           # Part of the textareas' ids: bumped after a save, so LiveView renders a fresh,
           # empty field instead of keeping what the browser holds.
           form_n: 0,
           editing_requester: false,
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
         |> assign(reply_form: reply_form(), form_n: socket.assigns.form_n + 1)
         |> reload()}

      {:error, :empty} ->
        {:noreply, put_flash(socket, :error, "Die Antwort ist leer.")}

      {:error, :replies_disabled} ->
        {:noreply, put_flash(socket, :error, "Antworten sind noch nicht eingerichtet.")}

      {:error, _} ->
        {:noreply, put_flash(socket, :error, "Antwort nicht gesendet.")}
    end
  end

  def handle_event("edit_requester", _params, socket),
    do: {:noreply, assign(socket, editing_requester: !socket.assigns.editing_requester)}

  def handle_event("requester", %{"name" => name, "email" => email}, socket) do
    %{current_scope: scope, ticket: ticket} = socket.assigns

    case Tickets.update_requester(scope, ticket, name, email) do
      {:ok, _} ->
        {:noreply,
         socket
         |> put_flash(:info, "Absender geändert.")
         |> assign(editing_requester: false)
         |> reload()}

      {:error, :invalid_email} ->
        {:noreply, put_flash(socket, :error, "Das ist keine gültige E-Mail-Adresse.")}

      {:error, _} ->
        {:noreply, put_flash(socket, :error, "Absender nicht geändert.")}
    end
  end

  def handle_event("note", %{"note" => %{"body" => body}}, socket) do
    case Tickets.add_note(socket.assigns.current_scope, socket.assigns.ticket, body) do
      {:ok, _} ->
        {:noreply,
         socket |> assign(note_form: note_form(), form_n: socket.assigns.form_n + 1) |> reload()}

      {:error, :empty} ->
        {:noreply, put_flash(socket, :error, "Die Notiz ist leer.")}

      {:error, _} ->
        {:noreply, put_flash(socket, :error, "Notiz nicht gespeichert.")}
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
          <span :if={@deleted} class="block text-sm">
            Wird am {purge_date(@ticket.deleted_at)} endgültig entfernt; bis dahin wiederherstellbar.
          </span>
        </:subtitle>
        <:actions>
          <.button navigate={~p"/admin/postfach"}>Zur Liste</.button>
        </:actions>
      </.header>

      <div class="mt-6 grid gap-6 lg:grid-cols-[1fr_20rem]">
        <div class="min-w-0 space-y-6">
          <.membership :if={@ticket.kind == "membership"} payload={@ticket.payload || %{}} />
          <.thread ticket={@ticket} />

          <.reply_form
            :if={can_reply?(@ticket, @deleted, @replies_enabled)}
            form={@reply_form}
            form_n={@form_n}
            ticket={@ticket}
          />
          <p
            :if={not @replies_enabled and not @deleted and @ticket.requester_email}
            class="text-sm text-base-content/60"
          >
            Antworten aus dem Postfach sind noch nicht eingerichtet (TICKET_SMTP_USERNAME).
          </p>

          <.note_form :if={not @deleted} form={@note_form} form_n={@form_n} />
        </div>

        <aside class="space-y-6">
          <section class="rounded-box bg-base-200 p-4 space-y-4">
            <.requester ticket={@ticket} editing={@editing_requester} deleted={@deleted} />
            <.assignment
              :if={not @deleted}
              ticket={@ticket}
              assignees={@assignees}
              user_id={@current_scope.user.id}
            />
            <.status :if={not @deleted} ticket={@ticket} choice={@status_choice} />
            <.move :if={not @deleted} ticket={@ticket} />
            <.actions ticket={@ticket} deleted={@deleted} can_delete={@can_delete} />
          </section>

          <.member_number :if={@ticket.kind == "membership" and not @deleted} ticket={@ticket} />
          <.related :if={@related != []} tickets={@related} />
          <.history events={@events} />
        </aside>
      </div>
    </Layouts.admin>
    """
  end

  defp purge_date(deleted_at) do
    deleted_at
    |> DateTime.add(Bbh.Tickets.Retention.purge_days(), :day)
    |> DateTime.shift_zone!(Bbh.Time.time_zone())
    |> Calendar.strftime("%d.%m.%Y")
  end

  defp can_reply?(ticket, deleted, enabled),
    do:
      enabled and not deleted and ticket.status != "spam" and
        ticket.requester_email not in [nil, ""]
end
