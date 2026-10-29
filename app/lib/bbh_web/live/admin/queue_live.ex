defmodule BbhWeb.Admin.QueueLive do
  @moduledoc """
  Admin-only: the Postfach's queues (`Bbh.Tickets.Queue`) — label, addresses, signature
  line, contact form, order, active. Who works a queue is set in the user
  administration.
  """
  use BbhWeb, :live_view

  alias Bbh.Tickets.Queue

  @impl true
  def mount(_params, _session, socket) do
    {:ok, assign(socket, page_title: "Postfächer", queues: Queue.all())}
  end

  @impl true
  def handle_params(params, _uri, socket) do
    {:noreply, apply_action(socket, socket.assigns.live_action, params)}
  end

  defp apply_action(socket, :index, _params), do: assign(socket, queue: nil, form: nil)

  defp apply_action(socket, :new, _params) do
    position = length(socket.assigns.queues)
    assign_form(socket, nil, Queue.create_changeset(%{"position" => position}))
  end

  defp apply_action(socket, :edit, %{"key" => key}) do
    case Queue.get(key) do
      nil ->
        socket
        |> put_flash(:error, "Postfach nicht gefunden.")
        |> push_patch(to: ~p"/admin/postfaecher")

      queue ->
        assign_form(socket, queue, Queue.changeset(queue, %{}))
    end
  end

  defp assign_form(socket, queue, changeset),
    do: assign(socket, queue: queue, form: to_form(changeset, as: "queue"))

  @impl true
  def handle_event("validate", %{"queue" => params}, socket) do
    changeset =
      case socket.assigns.queue do
        nil -> Queue.create_changeset(params)
        queue -> Queue.changeset(queue, params)
      end

    {:noreply, assign_form(socket, socket.assigns.queue, Map.put(changeset, :action, :validate))}
  end

  def handle_event("save", %{"queue" => params}, socket) do
    result =
      case socket.assigns.queue do
        nil -> Queue.create(params)
        queue -> Queue.update(queue, params)
      end

    case result do
      {:ok, saved} ->
        {:noreply,
         socket
         |> put_flash(:info, "Postfach „#{saved.label}“ gespeichert.")
         |> assign(queues: Queue.all())
         |> push_patch(to: ~p"/admin/postfaecher")}

      {:error, changeset} ->
        {:noreply, assign_form(socket, socket.assigns.queue, changeset)}
    end
  end

  def handle_event("delete", %{"key" => key}, socket) do
    message =
      case Queue.get(key) && Queue.delete(Queue.get(key)) do
        {:ok, _} ->
          {:info, "Postfach gelöscht."}

        {:error, :protected} ->
          {:error, "Dieses Postfach wird von der Website gebraucht."}

        {:error, :has_tickets} ->
          {:error, "Es gibt Anfragen in diesem Postfach – bitte deaktivieren statt löschen."}

        {:error, :has_grants} ->
          {:error, "Es gibt noch Freigaben für dieses Postfach (Benutzerverwaltung)."}

        _ ->
          {:error, "Postfach nicht gelöscht."}
      end

    {kind, text} = message

    {:noreply,
     socket
     |> put_flash(kind, text)
     |> assign(queues: Queue.all())
     |> push_patch(to: ~p"/admin/postfaecher")}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.admin flash={@flash} current_scope={@current_scope} active={:tickets}>
      <.header>
        Postfächer
        <:subtitle>
          Wohin Anfragen gehen und mit welcher Adresse geantwortet wird. Wer ein Postfach
          bearbeitet, steht in der <.link navigate={~p"/admin/benutzer"} class="link">Benutzerverwaltung</.link>.
        </:subtitle>
        <:actions>
          <.button navigate={~p"/admin/postfach"}>Zum Postfach</.button>
          <.button variant="primary" patch={~p"/admin/postfaecher/neu"}>Neues Postfach</.button>
        </:actions>
      </.header>

      <.table id="queues" rows={@queues} row_click={&JS.patch(~p"/admin/postfaecher/#{&1.key}")}>
        <:col :let={q} label="Postfach">
          <span class="font-medium">{q.label}</span>
          <span class="ml-1 font-mono text-xs text-base-content/60">{q.key}</span>
          <span :if={not q.active} class="badge badge-ghost badge-sm ml-1">inaktiv</span>
        </:col>
        <:col :let={q} label="Eingang">{Queue.inbound_address(q.key) || "– nur Formular –"}</:col>
        <:col :let={q} label="Antwort von">{Queue.reply_address(q.key) || "–"}</:col>
        <:col :let={q} label="Kontaktformular">{if q.in_contact_form, do: "ja", else: "–"}</:col>
        <:action :let={q}>
          <.link
            :if={not Queue.protected?(q.key)}
            phx-click={JS.push("delete", value: %{key: q.key})}
            data-confirm={"Postfach „#{q.label}“ löschen?"}
            class="link link-error"
            title="Löschen"
            aria-label="Löschen"
          >
            <.icon name="hero-trash" class="size-5" />
          </.link>
        </:action>
      </.table>

      <section :if={@form} class="mt-8 rounded-box border border-base-300 p-4">
        <h2 class="mb-4 text-lg font-semibold">
          {if @queue, do: "„#{@queue.label}“ bearbeiten", else: "Neues Postfach"}
        </h2>

        <.form for={@form} id="queue-form" phx-change="validate" phx-submit="save" class="space-y-2">
          <.input
            :if={is_nil(@queue)}
            field={@form[:key]}
            label="Schlüssel (dauerhaft, z. B. social)"
            placeholder="social"
          />
          <.input field={@form[:label]} label="Bezeichnung" placeholder="Social Media" />
          <.input
            field={@form[:inbound_address]}
            type="email"
            label="Eingangsadresse (Alias von tickets@ in mailcow)"
            placeholder="insta@buterland-beckerhook.de"
          />
          <.input
            field={@form[:reply_address]}
            type="email"
            label="Antworten von (leer: die Eingangsadresse)"
          />
          <.input
            field={@form[:signature]}
            label="Zeile unter Antworten und im Absendernamen (leer: nur der Verein)"
          />
          <div class="grid gap-4 sm:grid-cols-3">
            <.input field={@form[:position]} type="number" label="Reihenfolge" />
            <.input field={@form[:in_contact_form]} type="checkbox" label="Im Kontaktformular" />
            <.input field={@form[:active]} type="checkbox" label="Aktiv" />
          </div>
          <p class="text-sm text-base-content/60">
            Eine neue Eingangsadresse braucht in mailcow einen Alias auf tickets@ — und die
            Erlaubnis für tickets@, als diese Adresse zu senden.
          </p>
          <div class="flex gap-2">
            <.button variant="primary" phx-disable-with="Speichere…">Speichern</.button>
            <.button patch={~p"/admin/postfaecher"}>Abbrechen</.button>
          </div>
        </.form>
      </section>
    </Layouts.admin>
    """
  end
end
