defmodule BbhWeb.Admin.TicketLive.ShowComponents do
  @moduledoc """
  The parts of a Postfach ticket page (`BbhWeb.Admin.TicketLive.Show`): the thread, the
  reply and note forms, the side panels and the history. Function components only — the
  events they send (`take`, `assign`, `status`, …) are handled by the LiveView.
  """
  use BbhWeb, :html

  alias Bbh.Tickets.{Queue, Ticket}

  @reply_statuses [
    {"Danach: Wartet auf Antwort", "waiting"},
    {"Danach: In Bearbeitung", "open"},
    {"Danach: Erledigt", "closed"}
  ]

  ## Thread

  attr :ticket, Ticket, required: true

  def thread(assigns) do
    ~H"""
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
            <a
              href={~p"/admin/postfach/#{Ticket.reference(@ticket)}/anhang/#{a.id}"}
              class="link"
              download
            >
              {a.filename}
            </a>
            <span class="text-base-content/60">({kb(a.size)})</span>
          </li>
        </ul>
      </article>
    </section>
    """
  end

  defp message_class("in"), do: "border-base-300"
  defp message_class("out"), do: "border-primary/40 bg-primary/5"
  defp message_class("note"), do: "border-warning/40 bg-warning/10"
  defp message_class(_system), do: "border-dashed border-base-300 text-sm text-base-content/70"

  defp message_label(%{direction: "in"} = m, %{kind: "contact"} = t),
    do: "Kontaktformular von #{sender(m, t)}"

  defp message_label(%{direction: "in"} = m, %{kind: "membership"} = t),
    do: "Mitgliedsantrag von #{sender(m, t)}"

  defp message_label(%{direction: "in"} = m, t), do: "E-Mail von #{sender(m, t)}"

  defp message_label(%{direction: "out", author: author} = m, _),
    do: "Antwort von #{author && author.email}#{if is_nil(m.sent_at), do: " · wird gesendet …"}"

  defp message_label(%{direction: "note", author: author}, _),
    do: "Notiz von #{author && author.email}"

  defp message_label(_message, _ticket), do: "System"

  # "Name (address)" as the message came in; the name from the ticket for forms.
  defp sender(%{from: from}, %{kind: kind, requester_name: name})
       when kind in ["contact", "membership"] and is_binary(name) and name != "",
       do: "#{name} (#{from})"

  defp sender(%{from: from}, _ticket), do: from || "unbekannt"

  defp kb(size) when size < 1024, do: "#{size} B"
  defp kb(size), do: "#{Float.round(size / 1024, 1)} KB"

  ## Reply and note

  attr :form, Phoenix.HTML.Form, required: true
  attr :form_n, :integer, required: true, doc: "part of the textarea id, bumped per save"
  attr :ticket, Ticket, required: true

  def reply_form(assigns) do
    assigns = assign(assigns, :statuses, @reply_statuses)

    ~H"""
    <.form
      for={@form}
      id="reply-form"
      phx-submit="reply"
      class="rounded-box border border-primary/40 p-4"
    >
      <.input
        field={@form[:body]}
        id={"reply-body-#{@form_n}"}
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
        <.input field={@form[:status]} type="select" options={@statuses} />
        <%!-- No phx-disable-with: it replaces the button text, spinner included.
              LiveView disables the button while the submit (and the mail) runs. --%>
        <.button
          class="btn btn-primary mb-2"
          data-confirm="Antwort jetzt an den Absender senden?"
        >
          <span class="loading loading-spinner loading-sm hidden phx-submit-loading:inline-block"></span>
          <span class="phx-submit-loading:hidden">Antwort senden</span>
          <span class="hidden phx-submit-loading:inline">Sende…</span>
        </.button>
      </div>
    </.form>
    """
  end

  attr :form, Phoenix.HTML.Form, required: true
  attr :form_n, :integer, required: true

  def note_form(assigns) do
    ~H"""
    <.form for={@form} id="note-form" phx-submit="note">
      <.input
        field={@form[:body]}
        id={"note-body-#{@form_n}"}
        type="textarea"
        label="Interne Notiz"
        rows="4"
        placeholder="Nur im Postfach sichtbar, geht nicht an den Absender."
      />
      <.button phx-disable-with="Speichere…">Notiz speichern</.button>
    </.form>
    """
  end

  ## Side panel

  attr :ticket, Ticket, required: true
  attr :editing, :boolean, required: true
  attr :deleted, :boolean, required: true

  def requester(assigns) do
    ~H"""
    <div>
      <div class="flex items-baseline justify-between gap-2">
        <h2 class="text-sm font-semibold">Absender</h2>
        <button :if={not @deleted} type="button" phx-click="edit_requester" class="link text-xs">
          {if @editing, do: "Abbrechen", else: "Ändern"}
        </button>
      </div>
      <div :if={not @editing}>
        <p>{@ticket.requester_name || "–"}</p>
        <p class="break-all text-sm">{@ticket.requester_email}</p>
      </div>
      <form :if={@editing} phx-submit="requester" id="requester-form" class="mt-2 space-y-2">
        <input
          name="name"
          value={@ticket.requester_name}
          placeholder="Name"
          aria-label="Name"
          class="input input-bordered input-sm w-full"
        />
        <input
          name="email"
          type="email"
          value={@ticket.requester_email}
          placeholder="E-Mail-Adresse"
          aria-label="E-Mail-Adresse"
          required
          class="input input-bordered input-sm w-full"
        />
        <.button class="btn btn-sm w-full">Speichern</.button>
      </form>
    </div>
    """
  end

  attr :ticket, Ticket, required: true
  attr :assignees, :list, required: true
  attr :user_id, :string, required: true, doc: "the viewer, who may take the ticket"

  # The assign, status and move forms save on change and opt out of form recovery (see
  # `BbhWeb.Admin.TicketLive.Show`).
  def assignment(assigns) do
    ~H"""
    <div class="space-y-2">
      <h2 class="text-sm font-semibold">Bearbeitung</h2>
      <.button
        :if={@ticket.assignee_id != @user_id}
        phx-click="take"
        class="btn btn-primary btn-sm w-full"
      >
        Übernehmen
      </.button>
      <form phx-change="assign" phx-auto-recover="ignore" id="assign-form">
        <label class="text-sm" for="assignee_id">Zugewiesen an</label>
        <select id="assignee_id" name="assignee_id" class="select select-bordered select-sm w-full">
          <option value="">– niemand –</option>
          <option :for={u <- @assignees} value={u.id} selected={u.id == @ticket.assignee_id}>
            {u.email}
          </option>
        </select>
      </form>
    </div>
    """
  end

  attr :ticket, Ticket, required: true
  attr :choice, :string, required: true, doc: "what the select shows (see `status_choice`)"

  def status(assigns) do
    ~H"""
    <div>
      <h2 class="text-sm font-semibold">Status</h2>
      <p class="mb-2"><.status_badge kind={:ticket} status={@ticket.status} /></p>
      <form phx-change="status" phx-auto-recover="ignore" id="status-form" class="space-y-2">
        <label class="sr-only" for="status-select">Status ändern</label>
        <select id="status-select" name="status" class="select select-bordered select-sm w-full">
          <%!-- "Neu" and "Spam" are never set by hand, but the select shows them. --%>
          <option
            :if={@choice not in Enum.map(Ticket.status_options(), &elem(&1, 1))}
            value={@choice}
            selected
            disabled
          >
            {Ticket.status_label(@choice)}
          </option>
          <option
            :for={{label, value} <- Ticket.status_options()}
            value={value}
            selected={value == @choice}
          >
            {label}
          </option>
        </select>
        <div :if={@choice == "follow_up"}>
          <label class="text-sm" for="follow_up_on">Wiedervorlage am</label>
          <%!-- flatpickr instead of a native date input, which renders in the
               browser's locale (e.g. MM/DD/YYYY) rather than DD.MM.YYYY. --%>
          <div id="dp-follow_up_on" phx-update="ignore">
            <input
              type="text"
              id="follow_up_on"
              name="follow_up_on"
              value={@ticket.follow_up_on && Date.to_iso8601(@ticket.follow_up_on)}
              autocomplete="off"
              placeholder="TT.MM.JJJJ"
              phx-hook="DatePicker"
              data-enable-time="false"
              class="input input-bordered input-sm w-full"
            />
          </div>
        </div>
      </form>
    </div>
    """
  end

  attr :ticket, Ticket, required: true

  def move(assigns) do
    ~H"""
    <form phx-change="move" phx-auto-recover="ignore" id="move-form">
      <label class="text-sm font-semibold" for="move-queue">Postfach</label>
      <select id="move-queue" name="queue" class="select select-bordered select-sm w-full">
        <option :for={{label, key} <- Queue.options()} value={key} selected={key == @ticket.queue}>
          {label}
        </option>
      </select>
    </form>
    """
  end

  attr :ticket, Ticket, required: true
  attr :deleted, :boolean, required: true
  attr :can_delete, :boolean, required: true

  def actions(assigns) do
    ~H"""
    <div class="flex flex-wrap gap-2 pt-2">
      <.button :if={not @deleted and @ticket.status == "spam"} phx-click="unspam" class="btn btn-sm">
        Kein Spam
      </.button>
      <.button
        :if={not @deleted and @ticket.status != "spam"}
        phx-click="spam"
        data-confirm="Als Spam markieren? Die E-Mail trainiert den Spamfilter des Mailservers – nur echten Spam markieren, keine erledigten oder unerwünschten Anfragen."
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
    """
  end

  attr :ticket, Ticket, required: true

  def member_number(assigns) do
    ~H"""
    <section class="rounded-box bg-base-200 p-4">
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
    """
  end

  attr :tickets, :list, required: true

  def related(assigns) do
    ~H"""
    <section class="rounded-box bg-base-200 p-4">
      <h2 class="text-sm font-semibold">Weitere Anfragen dieses Absenders</h2>
      <ul class="mt-2 space-y-1 text-sm">
        <li :for={t <- @tickets}>
          <.link navigate={~p"/admin/postfach/#{Ticket.reference(t)}"} class="link">
            {Ticket.reference(t)}
          </.link>
          {t.subject}
        </li>
      </ul>
    </section>
    """
  end

  attr :events, :list, required: true

  def history(assigns) do
    ~H"""
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
    """
  end

  @event_labels %{
    "created" => "eingegangen",
    "viewed" => "angesehen",
    "assigned" => "Zuweisung geändert",
    "status_changed" => "Status geändert",
    "queue_changed" => "Postfach gewechselt",
    "replied" => "beantwortet",
    "noted" => "Notiz",
    "requester_changed" => "Absender geändert",
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

  ## Membership application

  attr :payload, :map, required: true

  def membership(assigns) do
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

  ## Time

  @doc "A UTC datetime as the club's local, short German date and time."
  def local(dt),
    do: dt |> DateTime.shift_zone!(Bbh.Time.time_zone()) |> BbhWeb.Format.de_short_datetime()

  defp local_iso(iso) do
    case DateTime.from_iso8601(iso) do
      {:ok, dt, _} -> local(dt)
      _ -> iso
    end
  end
end
