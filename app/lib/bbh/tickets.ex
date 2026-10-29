defmodule Bbh.Tickets do
  @moduledoc """
  The Postfach: requests from the contact and membership forms (and, later, mail to the
  club addresses) as tickets in queues, worked by the users granted that queue.

  This context is the only place that sees clear text. Personal data is encrypted with
  `Bbh.Vault` on the way in and decrypted on the way out; lists, filters and reminders
  run on the plain columns (queue, status, assignee, dates). Every function that acts
  for a person takes their `Bbh.Accounts.Scope` and authorizes through `BbhWeb.Authz`.

  Every change is broadcast on the `"tickets"` PubSub topic, so open lists and tickets
  update in place, and recorded in `ticket_events` — without personal data.

  See `docs/plans/ticket-system.md`.
  """
  import Ecto.Query

  alias Bbh.Accounts.{Scope, User}
  alias Bbh.Repo
  alias Bbh.Tickets.{Attachment, Event, Grant, Message, Queue, Ticket}
  alias Bbh.Vault
  alias BbhWeb.Authz

  @topic "tickets"
  @page_size 50
  # A ticket opened again within this window is not logged as a second view.
  @view_throttle_minutes 10

  @doc "Whether the Postfach replaces the old mail path (`TICKETS_ENABLED`)."
  def enabled?, do: Application.get_env(:bbh, :tickets_enabled, false) == true

  @doc "Subscribes the caller to ticket changes (`{:tickets_changed, ticket_id}`)."
  def subscribe, do: Phoenix.PubSub.subscribe(Bbh.PubSub, @topic)

  defp broadcast(%Ticket{id: id}),
    do: Phoenix.PubSub.broadcast(Bbh.PubSub, @topic, {:tickets_changed, id})

  ## Creating

  @doc """
  Creates a ticket with its first message, both encrypted.

  `attrs`: `:queue`, `:kind`, `:subject`, `:requester_name`, `:requester_email`,
  `:payload` (map), optional `:status` (`new` or `spam`) and `:spam_score`.
  `message`: `:body`, optional `:from`, `:to` and the mail/IMAP identifiers.
  """
  def create_ticket(attrs, message) do
    Repo.transact(fn ->
      changeset =
        %Ticket{}
        |> Ticket.create_changeset(attrs)
        |> Ecto.Changeset.put_change(
          :requester_email_hmac,
          Vault.blind_index(attrs[:requester_email])
        )
        |> Vault.encrypt_changes("tickets", Ticket.encrypted_fields())

      with {:ok, ticket} <- Repo.insert(changeset),
           {:ok, _message} <- insert_message(ticket, Map.put(message, :direction, "in")) do
        log_event(ticket, nil, "created", %{kind: ticket.kind, queue: ticket.queue})
        {:ok, ticket}
      end
    end)
    |> tap_ok(&broadcast/1)
  end

  @doc """
  A contact-form request as a ticket in `queue` (one the form offers, else the default).
  The subject is the message's first line, shortened — the form has no subject field.
  Contact tickets store no IP address.
  """
  def create_from_contact(%{name: name, email: email, message: message}, queue) do
    queue = if Queue.in_contact_form?(queue), do: queue, else: Queue.default()

    create_ticket(
      %{
        queue: queue,
        kind: "contact",
        subject: contact_subject(message),
        requester_name: name,
        requester_email: email
      },
      %{body: message, from: email}
    )
  end

  defp contact_subject(message) do
    line = message |> String.split("\n", parts: 2) |> hd() |> String.trim()
    if String.length(line) > 80, do: String.slice(line, 0, 79) <> "…", else: line
  end

  @doc """
  A membership application as a ticket in `mitgliedschaft`. `data` is the validated
  form (`Bbh.Membership.validate/1`); `record` the submission record that stands in for
  date and signature: `:submitted_at`, `:client_ip`, `:altcha_verified`. Everything goes
  into the encrypted payload, together with the form version and the age flags.
  """
  def create_from_membership(data, record) do
    name = Bbh.Membership.full_name(data)

    payload =
      data
      |> Map.merge(%{
        flags: Bbh.Membership.flags(data),
        submitted_at: record.submitted_at,
        client_ip: record.client_ip,
        altcha_verified: record.altcha_verified,
        form_version: Bbh.Membership.form_version(),
        sepa_mandate: data.sepa
      })
      # Through JSON once, so the struct in hand looks like one loaded later.
      |> Jason.encode!()
      |> Jason.decode!()

    create_ticket(
      %{
        queue: "mitgliedschaft",
        kind: "membership",
        subject: "Aufnahmeantrag #{name}",
        requester_name: name,
        requester_email: data.email,
        payload: payload
      },
      %{body: "Aufnahmeantrag über die Website.", from: data.email}
    )
  end

  defp insert_message(%Ticket{id: ticket_id}, attrs) do
    %Message{}
    |> Message.changeset(Map.put(attrs, :ticket_id, ticket_id))
    |> Vault.encrypt_changes("ticket_messages", Message.encrypted_fields())
    |> Repo.insert()
  end

  ## Reading

  @doc """
  One page of the tickets the scope may see. Filters work on plain columns only.

  Options: `:queue` (nil: all visible), `:view` — `"open"` (in work, nobody assigned;
  the default), `"mine"`, `"overdue"`, `"all"` (everything in work), `"closed"`,
  `"spam"`, `"deleted"` (admins) — and `:page` (1-based).
  Returns `%{entries:, page:, total_pages:, total:}` with subjects decrypted.
  """
  def list_tickets(%Scope{} = scope, opts \\ []) do
    page = max(opts[:page] || 1, 1)

    query =
      scope
      |> visible_query(opts[:queue])
      |> filter_view(opts[:view] || "open", scope)

    total = Repo.aggregate(query, :count)

    entries =
      query
      |> order_by([t], desc: t.last_activity_at, desc: t.number)
      |> limit(@page_size)
      |> offset(^((page - 1) * @page_size))
      |> preload(:assignee)
      |> Repo.all()
      |> Enum.map(&Vault.decrypt_fields(&1, "tickets", [{:subject, :subject_enc}]))

    %{
      entries: entries,
      page: page,
      total: total,
      total_pages: max(div(total + @page_size - 1, @page_size), 1)
    }
  end

  defp visible_query(scope, queue) do
    queues = Authz.visible_queues(scope)
    queues = if queue in queues, do: [queue], else: queues
    from t in Ticket, where: t.queue in ^queues
  end

  defp filter_view(query, "deleted", scope) do
    if Authz.can_delete_ticket?(scope),
      do: where(query, [t], not is_nil(t.deleted_at)),
      else: where(query, false)
  end

  defp filter_view(query, view, scope) do
    query = where(query, [t], is_nil(t.deleted_at))

    case view do
      "open" ->
        where(query, [t], t.status in ^Ticket.active_statuses() and is_nil(t.assignee_id))

      "mine" ->
        where(
          query,
          [t],
          t.assignee_id == ^scope.user.id and t.status in ^Ticket.active_statuses()
        )

      "overdue" ->
        Bbh.Tickets.Reminders.overdue(query, Bbh.Settings.get())

      "closed" ->
        where(query, [t], t.status == "closed")

      "spam" ->
        where(query, [t], t.status == "spam")

      _all ->
        where(query, [t], t.status in ^Ticket.active_statuses())
    end
  end

  @doc """
  Counts for the list's tabs that carry a number: `%{"open" => n, "mine" => n,
  "overdue" => n}`, within `queue` (nil: all visible).
  """
  def count_views(%Scope{} = scope, queue \\ nil) do
    for view <- ~w(open mine overdue), into: %{} do
      count =
        scope
        |> visible_query(queue)
        |> filter_view(view, scope)
        |> Repo.aggregate(:count)

      {view, count}
    end
  end

  @doc "Count of `new` tickets in the scope's queues — the dashboard widget."
  def count_new(%Scope{} = scope) do
    scope
    |> visible_query(nil)
    |> where([t], t.status == "new" and is_nil(t.deleted_at))
    |> Repo.aggregate(:count)
  end

  def count_new(_), do: 0

  @doc "Active tickets assigned to the scope's user — the dashboard widget."
  def list_assigned(%Scope{} = scope, limit \\ 10) do
    scope
    |> visible_query(nil)
    |> filter_view("mine", scope)
    |> order_by([t], asc: t.follow_up_on, desc: t.last_activity_at)
    |> limit(^limit)
    |> Repo.all()
    |> Enum.map(&Vault.decrypt_fields(&1, "tickets", [{:subject, :subject_enc}]))
  end

  @doc """
  The ticket with this number (or reference, "BB-2026-0042"), decrypted, with its thread
  and attachment names (not their contents). `{:error, :not_found}` when it does not
  exist or the scope may not see it — the two are indistinguishable on purpose.
  """
  def get_ticket(%Scope{} = scope, reference) do
    number = if is_integer(reference), do: reference, else: Ticket.parse_reference(reference)

    attachments =
      from a in Attachment,
        select: struct(a, [:id, :ticket_message_id, :filename_enc, :content_type, :size]),
        order_by: a.inserted_at

    with number when is_integer(number) <- number,
         %Ticket{} = ticket <- Repo.get_by(Ticket, number: number),
         true <- Authz.can_view_ticket?(scope, ticket),
         true <- is_nil(ticket.deleted_at) or Authz.can_delete_ticket?(scope) do
      ticket =
        ticket
        |> Repo.preload([
          :assignee,
          messages: {messages_query(), [:author, attachments: attachments]}
        ])
        |> decrypt_ticket()

      {:ok, ticket}
    else
      _ -> {:error, :not_found}
    end
  end

  defp messages_query, do: from(m in Message, order_by: [asc: m.inserted_at, asc: m.id])

  defp decrypt_ticket(ticket) do
    ticket = Vault.decrypt_fields(ticket, "tickets", Ticket.encrypted_fields())

    messages =
      for message <- ticket.messages do
        message = Vault.decrypt_fields(message, "ticket_messages", Message.encrypted_fields())

        attachments =
          Enum.map(
            message.attachments,
            &Vault.decrypt_fields(&1, "ticket_attachments", [{:filename, :filename_enc}])
          )

        %{message | attachments: attachments}
      end

    %{ticket | messages: messages}
  end

  @doc "The history of a ticket, oldest first, with the acting users."
  def list_events(%Ticket{id: id}) do
    Repo.all(
      from e in Event,
        where: e.ticket_id == ^id,
        order_by: [asc: e.inserted_at, asc: e.id],
        preload: :user
    )
  end

  @doc """
  Other tickets of the same requester (matched by the e-mail blind index) that the
  scope may see — "weitere Tickets dieses Absenders".
  """
  def related_tickets(%Scope{} = scope, %Ticket{requester_email_hmac: hmac, id: id})
      when is_binary(hmac) do
    scope
    |> visible_query(nil)
    |> where([t], t.requester_email_hmac == ^hmac and t.id != ^id and is_nil(t.deleted_at))
    |> order_by([t], desc: t.inserted_at)
    |> Repo.all()
    |> Enum.map(&Vault.decrypt_fields(&1, "tickets", [{:subject, :subject_enc}]))
  end

  def related_tickets(_scope, _ticket), do: []

  @doc "The users a ticket can be assigned to: those granted its queue, plus admins."
  def assignable_users(%Ticket{queue: queue}) do
    Repo.all(
      from u in User,
        left_join: g in Grant,
        on: g.user_id == u.id and g.queue_key == ^queue,
        where: u.role == "admin" or not is_nil(g.id),
        distinct: true,
        order_by: u.email
    )
  end

  ## Working a ticket

  @doc "The scope's user takes the ticket: assigned to them, `new` becomes `open`."
  def take(%Scope{user: user} = scope, %Ticket{} = ticket), do: assign(scope, ticket, user.id)

  @doc "Assigns the ticket (nil: nobody). The assignee must be able to see its queue."
  def assign(%Scope{} = scope, %Ticket{} = ticket, assignee_id) do
    assignee_id = if assignee_id in [nil, ""], do: nil, else: assignee_id

    with :ok <- authorize(scope, ticket),
         :ok <- check_assignee(ticket, assignee_id) do
      status = if ticket.status == "new" and assignee_id, do: "open", else: ticket.status

      ticket
      |> Ecto.Changeset.change(
        assignee_id: assignee_id,
        status: status,
        last_activity_at: DateTime.utc_now(:second)
      )
      |> update_and_log(scope, "assigned", %{assignee_id: assignee_id})
      |> tap_ok(&notify_assignee(&1, scope.user))
    end
  end

  defp check_assignee(_ticket, nil), do: :ok

  defp check_assignee(ticket, assignee_id) do
    if Enum.any?(assignable_users(ticket), &(&1.id == assignee_id)),
      do: :ok,
      else: {:error, :invalid_assignee}
  end

  @doc """
  Sets the status (`open`, `waiting`, `follow_up` with a date, `closed`). Returns
  `{:error, changeset}` for a follow-up without a date.
  """
  def set_status(%Scope{} = scope, %Ticket{} = ticket, status, follow_up_on \\ nil) do
    with :ok <- authorize(scope, ticket),
         true <- status in ~w(open waiting follow_up closed) || {:error, :invalid_status} do
      ticket
      |> Ticket.status_changeset(status, parse_date(follow_up_on))
      |> update_and_log(scope, "status_changed", %{from: ticket.status, to: status})
    end
  end

  defp parse_date(%Date{} = date), do: date

  defp parse_date(value) when is_binary(value) do
    case Date.from_iso8601(value) do
      {:ok, date} -> date
      _ -> nil
    end
  end

  defp parse_date(_), do: nil

  ## Replies

  @doc "Whether replies can be sent from the Postfach (`Bbh.TicketMailer` configured)."
  def replies_enabled?, do: Bbh.TicketMailer.enabled?()

  @doc """
  Answers the requester from the queue's address (`Bbh.Tickets.ReplyMail`). The reply
  is stored, the ticket set to `status` (`waiting` by default, or `open`/`closed`) and
  taken by the replier if nobody had it; the mail itself goes out in a job
  (`Bbh.Workers.TicketReplySender`).
  """
  def reply(%Scope{user: user} = scope, %Ticket{} = ticket, body, status \\ "waiting") do
    body = String.trim(body || "")

    with :ok <- authorize(scope, ticket),
         true <- replies_enabled?() || {:error, :replies_disabled},
         true <- ticket.requester_email not in [nil, ""] || {:error, :no_recipient},
         true <- ticket.status != "spam" || {:error, :spam},
         true <- body != "" || {:error, :empty},
         true <- status in ~w(open waiting closed) || {:error, :invalid_status} do
      Repo.transact(fn ->
        message_attrs = %{
          direction: "out",
          author_id: user.id,
          from: Queue.reply_address(ticket.queue),
          to: ticket.requester_email,
          body: body,
          message_id: "<#{Ecto.UUID.generate()}@buterland-beckerhook.de>"
        }

        with {:ok, message} <- insert_message(ticket, message_attrs),
             {:ok, updated} <-
               ticket
               |> Ticket.status_changeset(status, nil)
               |> Ecto.Changeset.put_change(:assignee_id, ticket.assignee_id || user.id)
               |> Repo.update() do
          log_event(updated, user, "replied", %{status: status})
          %{message_id: message.id} |> Bbh.Workers.TicketReplySender.new() |> Oban.insert!()
          {:ok, updated}
        end
      end)
      |> tap_ok(&broadcast/1)
    end
  end

  @doc false
  # Sends a stored reply (called by Bbh.Workers.TicketReplySender). `:ok` also when it
  # already went out or is gone; `{:error, :delivery_failed}` to retry — the reason
  # itself is logged by the mailer, not stored in the job (it may name the address).
  def deliver_reply(message_id) do
    with %Message{direction: "out", sent_at: nil} = message <- Repo.get(Message, message_id),
         %Ticket{} = ticket <- Repo.get(Ticket, message.ticket_id) do
      message = Vault.decrypt_fields(message, "ticket_messages", Message.encrypted_fields())
      ticket = Vault.decrypt_fields(ticket, "tickets", Ticket.encrypted_fields())
      email = Bbh.Tickets.ReplyMail.build(ticket, message, latest_inbound(ticket))

      case Bbh.Mailer.deliver_logged(email, "ticket-reply",
             redact: true,
             mailer: Bbh.TicketMailer
           ) do
        {:ok, _} ->
          message |> Ecto.Changeset.change(sent_at: DateTime.utc_now(:second)) |> Repo.update!()
          broadcast(ticket)
          :ok

        {:error, _reason} ->
          {:error, :delivery_failed}
      end
    else
      _ -> :ok
    end
  end

  @doc false
  # The last attempt failed: say so on the ticket.
  def reply_failed(message_id) do
    with %Message{} = message <- Repo.get(Message, message_id),
         %Ticket{} = ticket <- Repo.get(Ticket, message.ticket_id) do
      date =
        message.inserted_at
        |> DateTime.shift_zone!(Bbh.Time.time_zone())
        |> Calendar.strftime("%d.%m.%Y, %H:%M Uhr")

      {:ok, _} =
        insert_message(ticket, %{
          direction: "system",
          body:
            "Die Antwort vom #{date} konnte nicht gesendet werden. Bitte die Adresse " <>
              "prüfen und erneut antworten."
        })

      broadcast(ticket)
    end

    :ok
  end

  defp latest_inbound(%Ticket{id: id}) do
    from(m in Message,
      where: m.ticket_id == ^id and m.direction == "in",
      order_by: [desc: m.inserted_at],
      limit: 1
    )
    |> Repo.one()
    |> case do
      nil -> nil
      message -> Vault.decrypt_fields(message, "ticket_messages", Message.encrypted_fields())
    end
  end

  @doc """
  Adds an inbound mail to an existing ticket (the requester answered, see
  `Bbh.Tickets.Threading`). A ticket that was waiting, on follow-up or closed is opened
  again; the assignee — or the queue, while nobody has it — is told.
  """
  def add_inbound(%Ticket{} = ticket, message_attrs) do
    Repo.transact(fn ->
      with {:ok, message} <- insert_message(ticket, Map.put(message_attrs, :direction, "in")) do
        reopen? = ticket.status in ~w(waiting follow_up closed)

        changes =
          if reopen?,
            do: [status: "open", closed_at: nil, follow_up_on: nil],
            else: []

        {:ok, updated} =
          ticket
          |> Ecto.Changeset.change([last_activity_at: DateTime.utc_now(:second)] ++ changes)
          |> Repo.update()

        log_event(updated, nil, "received", %{reopened: reopen?})
        {:ok, {updated, message}}
      end
    end)
    |> tap_ok(fn {updated, _message} ->
      broadcast(updated)
      notify_reply(updated)
    end)
  end

  defp notify_reply(%Ticket{assignee_id: nil, queue: queue} = ticket) do
    for user <- Bbh.Tickets.Grants.notify_users(queue),
        do: Bbh.Tickets.Notifier.reply_received(user, ticket)
  end

  defp notify_reply(%Ticket{assignee_id: id} = ticket) do
    case Repo.get(User, id) do
      nil -> notify_reply(%{ticket | assignee_id: nil})
      user -> Bbh.Tickets.Notifier.reply_received(user, ticket)
    end
  end

  @doc "Adds an internal note. Notes never leave the system."
  def add_note(%Scope{user: user} = scope, %Ticket{} = ticket, body) do
    body = String.trim(body || "")

    with :ok <- authorize(scope, ticket),
         true <- body != "" || {:error, :empty} do
      Repo.transact(fn ->
        with {:ok, _} <-
               insert_message(ticket, %{direction: "note", author_id: user.id, body: body}) do
          ticket
          |> Ecto.Changeset.change(last_activity_at: DateTime.utc_now(:second))
          |> update_and_log(scope, "noted", %{})
        end
      end)
    end
  end

  @doc "Moves the ticket to another queue (a request that landed in the wrong one)."
  def move_queue(%Scope{} = scope, %Ticket{} = ticket, queue) do
    with :ok <- authorize(scope, ticket),
         true <- Queue.valid?(queue) || {:error, :invalid_queue} do
      # The assignee may not see the new queue; whoever works it there takes it anew.
      # A ticket still in work is news to the new queue (Bbh.Workers.TicketNewNotifier).
      in_work? = ticket.status in Ticket.active_statuses()

      ticket
      |> Ecto.Changeset.change(
        queue: queue,
        assignee_id: nil,
        status: if(in_work?, do: "new", else: ticket.status),
        notified_at: if(in_work?, do: nil, else: ticket.notified_at)
      )
      |> update_and_log(scope, "queue_changed", %{from: ticket.queue, to: queue})
    end
  end

  @doc "Marks the ticket as spam."
  def mark_spam(%Scope{} = scope, %Ticket{} = ticket) do
    with :ok <- authorize(scope, ticket) do
      ticket
      |> Ecto.Changeset.change(status: "spam", last_activity_at: DateTime.utc_now(:second))
      |> update_and_log(scope, "marked_spam", %{from: ticket.status})
    end
  end

  @doc """
  Takes back a spam marking: the ticket returns to `new` when nobody has it, else to
  `open`.
  """
  def unmark_spam(%Scope{} = scope, %Ticket{status: "spam"} = ticket) do
    with :ok <- authorize(scope, ticket) do
      status = if ticket.assignee_id, do: "open", else: "new"

      ticket
      |> Ecto.Changeset.change(status: status, last_activity_at: DateTime.utc_now(:second))
      |> update_and_log(scope, "unmarked_spam", %{to: status})
    end
  end

  def unmark_spam(_scope, _ticket), do: {:error, :not_spam}

  @doc "Soft-deletes the ticket (admins). Purged later with everything in it."
  def delete_ticket(%Scope{} = scope, %Ticket{} = ticket) do
    if Authz.can_delete_ticket?(scope) do
      ticket
      |> Ecto.Changeset.change(deleted_at: DateTime.utc_now(:second))
      |> update_and_log(scope, "deleted", %{})
    else
      {:error, :unauthorized}
    end
  end

  @doc "Restores a soft-deleted ticket (admins)."
  def restore_ticket(%Scope{} = scope, %Ticket{} = ticket) do
    if Authz.can_delete_ticket?(scope) do
      ticket
      |> Ecto.Changeset.change(deleted_at: nil)
      |> update_and_log(scope, "restored", %{})
    else
      {:error, :unauthorized}
    end
  end

  @doc """
  Sets the Mitgliedsnummer on a membership ticket (stored encrypted in the payload; it
  is also the SEPA mandate reference).
  """
  def set_member_number(%Scope{} = scope, %Ticket{kind: "membership"} = ticket, number) do
    with :ok <- authorize(scope, ticket) do
      payload = Map.put(ticket.payload || %{}, "member_number", String.trim(number || ""))

      ticket
      |> Ecto.Changeset.change(payload: payload)
      |> Vault.encrypt_changes("tickets", Ticket.encrypted_fields())
      |> update_and_log(scope, "member_number_set", %{})
    end
  end

  def set_member_number(_scope, _ticket, _number), do: {:error, :not_membership}

  @doc """
  The membership application of a ticket as PDF (`Bbh.Tickets.Pdf`), logged as
  `pdf_exported`. The PDF is returned, never stored.
  """
  def export_pdf(%Scope{user: user} = scope, %Ticket{kind: "membership"} = ticket) do
    with :ok <- authorize_view(scope, ticket),
         {:ok, pdf} <- Bbh.Tickets.Pdf.membership_application(ticket, user) do
      log_event(ticket, user, "pdf_exported", %{})
      {:ok, pdf}
    end
  end

  def export_pdf(_scope, _ticket), do: {:error, :not_membership}

  defp authorize_view(scope, ticket) do
    if Authz.can_view_ticket?(scope, ticket), do: :ok, else: {:error, :unauthorized}
  end

  @doc "Logs that the scope's user opened the ticket — once per 10 minutes."
  def record_view(%Scope{user: user}, %Ticket{} = ticket) do
    since = DateTime.utc_now(:second) |> DateTime.add(-@view_throttle_minutes, :minute)

    seen? =
      Repo.exists?(
        from e in Event,
          where:
            e.ticket_id == ^ticket.id and e.user_id == ^user.id and e.action == "viewed" and
              e.inserted_at > ^since
      )

    unless seen?, do: log_event(ticket, user, "viewed", %{})
    :ok
  end

  @doc "Logs an action, on a ticket or none (`grants_changed`). `meta` never carries personal data."
  def log_event(%Ticket{} = ticket, user, action, meta) do
    Repo.insert!(%Event{
      ticket_id: ticket.id,
      ticket_number: ticket.number,
      user_id: user && user.id,
      action: action,
      meta: meta
    })
  end

  # Without a ticket: `grants_changed`.
  def log_event(nil, user, action, meta) do
    Repo.insert!(%Event{user_id: user && user.id, action: action, meta: meta})
  end

  defp authorize(scope, ticket) do
    if Authz.can_handle_ticket?(scope, ticket) and is_nil(ticket.deleted_at),
      do: :ok,
      else: {:error, :unauthorized}
  end

  # Updates, logs and broadcasts; returns the ticket with its clear-text fields kept.
  defp update_and_log(changeset, %Scope{user: user}, action, meta) do
    with {:ok, updated} <- Repo.update(changeset) do
      log_event(updated, user, action, meta)
      broadcast(updated)
      {:ok, updated}
    end
  end

  # Someone else assigned it: tell the assignee (ids only in the job).
  defp notify_assignee(%Ticket{assignee_id: nil}, _by), do: :ok
  defp notify_assignee(%Ticket{assignee_id: id}, %User{id: id}), do: :ok

  defp notify_assignee(%Ticket{} = ticket, %User{} = by) do
    %{ticket_id: ticket.id, assignee_id: ticket.assignee_id, by_id: by.id}
    |> Bbh.Workers.TicketAssignedNotifier.new()
    |> Oban.insert!()
  end

  defp tap_ok({:ok, value} = result, fun) do
    fun.(value)
    result
  end

  defp tap_ok(other, _fun), do: other
end
