defmodule BbhWeb.Admin.SiteSettingsLive do
  @moduledoc """
  Admin-only site settings, in two tabs: the homepage notice banner and push quiet hours,
  and the Postfach's reminders (hour, thresholds, admin digest).
  """
  use BbhWeb, :live_view

  alias Bbh.Settings

  @hours for h <- 0..23, do: {String.pad_leading(Integer.to_string(h), 2, "0") <> ":00", h}

  @impl true
  def mount(_params, _session, socket) do
    settings = Settings.get()

    {:ok,
     socket
     |> assign(page_title: "Website", hours: @hours)
     |> assign_form(Settings.change(settings))
     |> assign_tickets_form(Settings.change_tickets(settings))}
  end

  @impl true
  def handle_params(_params, _uri, socket), do: {:noreply, socket}

  @impl true
  def handle_event("validate", %{"site_settings" => params}, socket) do
    changeset =
      Settings.get()
      |> Settings.change(params)
      |> Map.put(:action, :validate)

    {:noreply, assign_form(socket, changeset)}
  end

  def handle_event("save", %{"site_settings" => params}, socket) do
    case Settings.update(params) do
      {:ok, settings} ->
        {:noreply,
         socket
         |> put_flash(:info, "Einstellungen gespeichert.")
         |> assign_form(Settings.change(settings))}

      {:error, changeset} ->
        {:noreply, assign_form(socket, changeset)}
    end
  end

  def handle_event("validate_tickets", %{"tickets" => params}, socket) do
    changeset =
      Settings.get()
      |> Settings.change_tickets(params)
      |> Map.put(:action, :validate)

    {:noreply, assign_tickets_form(socket, changeset)}
  end

  def handle_event("save_tickets", %{"tickets" => params}, socket) do
    case Settings.update_tickets(params) do
      {:ok, settings} ->
        {:noreply,
         socket
         |> put_flash(:info, "Einstellungen gespeichert.")
         |> assign_tickets_form(Settings.change_tickets(settings))}

      {:error, changeset} ->
        {:noreply, assign_tickets_form(socket, changeset)}
    end
  end

  defp assign_form(socket, changeset),
    do: assign(socket, :form, to_form(changeset, as: "site_settings"))

  defp assign_tickets_form(socket, changeset),
    do: assign(socket, :tickets_form, to_form(changeset, as: "tickets"))

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.admin flash={@flash} current_scope={@current_scope} active={:site_settings}>
      <.header>
        Website
        <:subtitle>Einstellungen für die ganze Website.</:subtitle>
      </.header>

      <div role="tablist" class="tabs tabs-box mt-6">
        <.link
          patch={~p"/admin/website"}
          role="tab"
          class={["tab", @live_action == :index && "tab-active"]}
        >
          Startseite & Push
        </.link>
        <.link
          patch={~p"/admin/website/postfach"}
          role="tab"
          class={["tab", @live_action == :tickets && "tab-active"]}
        >
          Postfach
        </.link>
      </div>

      <.form
        :if={@live_action == :tickets}
        for={@tickets_form}
        id="tickets-settings-form"
        phx-change="validate_tickets"
        phx-submit="save_tickets"
        class="mt-6 space-y-8"
      >
        <fieldset class="rounded-box border border-base-300 p-4">
          <legend class="px-1 text-sm font-medium">Erinnerungen</legend>
          <.input
            field={@tickets_form[:ticket_reminder_hour]}
            type="select"
            label="Erinnerungen versenden um"
            options={@hours}
          />
          <p class="mt-1 text-sm text-base-content/60">
            Höchstens eine Erinnerungsmail pro Person und Tag, mit allen Anfragen, die warten.
            Zeiten in {Bbh.Time.time_zone()}.
          </p>
          <div class="mt-4 grid gap-4 sm:grid-cols-2">
            <.input
              field={@tickets_form[:ticket_remind_unassigned_hours]}
              type="number"
              min="1"
              max="168"
              label="Neu und niemandem zugewiesen nach (Stunden)"
            />
            <.input
              field={@tickets_form[:ticket_remind_idle_days]}
              type="number"
              min="1"
              max="90"
              label="In Bearbeitung ohne Aktivität nach (Tagen)"
            />
            <.input
              field={@tickets_form[:ticket_remind_waiting_days]}
              type="number"
              min="1"
              max="90"
              label="Wartet auf Antwort nach (Tagen)"
            />
          </div>
          <p class="mt-1 text-sm text-base-content/60">
            Diese Werte bestimmen auch, was im Postfach als „Überfällig“ gilt. Eine fällige
            Wiedervorlage erinnert immer.
          </p>
        </fieldset>

        <fieldset class="rounded-box border border-base-300 p-4">
          <legend class="px-1 text-sm font-medium">Tagesübersicht für Administratoren</legend>
          <.input
            field={@tickets_form[:ticket_admin_digest_enabled]}
            type="checkbox"
            label="Tagesübersicht an Administratoren senden"
          />
          <.input
            field={@tickets_form[:ticket_escalate_days]}
            type="number"
            min="1"
            max="90"
            label="Hervorheben, wenn seit (Tagen) niemandem zugewiesen"
          />
          <p class="mt-1 text-sm text-base-content/60">
            Anzahl je Postfach und Status, überfällige Anfragen und lange unbearbeitete.
            Entfällt an Tagen, an denen nichts überfällig ist.
          </p>
        </fieldset>

        <div class="flex gap-2">
          <.button variant="primary" phx-disable-with="Speichern…">Speichern</.button>
        </div>
      </.form>

      <.form
        :if={@live_action == :index}
        for={@form}
        id="site-settings-form"
        phx-change="validate"
        phx-submit="save"
        class="mt-6 space-y-8"
      >
        <fieldset class="rounded-box border border-base-300 p-4">
          <legend class="px-1 text-sm font-medium">Hinweis auf der Startseite</legend>
          <.input
            field={@form[:home_notice_enabled]}
            type="checkbox"
            label="Hinweis anzeigen"
          />
          <.input
            field={@form[:home_notice_text]}
            type="textarea"
            label="Text"
            rows="3"
            placeholder="z. B. Das Sommerfest fällt wegen des Wetters aus."
          />
          <p class="mt-1 text-sm text-base-content/60">
            Erscheint als Banner oben auf der Startseite. Einfache Links sind erlaubt.
          </p>
        </fieldset>

        <fieldset class="rounded-box border border-base-300 p-4">
          <legend class="px-1 text-sm font-medium">Ruhezeiten (keine Push-Nachrichten)</legend>
          <.input
            field={@form[:quiet_hours_enabled]}
            type="checkbox"
            label="Nachts keine Push-Nachrichten senden"
          />
          <div class="mt-3 grid gap-4 sm:grid-cols-2">
            <.input field={@form[:quiet_hours_start]} type="select" label="Von" options={@hours} />
            <.input field={@form[:quiet_hours_end]} type="select" label="Bis" options={@hours} />
          </div>
          <p class="mt-1 text-sm text-base-content/60">
            Fällige Erinnerungen und Ankündigungen werden zurückgehalten und nach dem Fenster
            automatisch nachgeholt. Zeiten in {Bbh.Time.time_zone()}.
          </p>
        </fieldset>

        <div class="flex gap-2">
          <.button variant="primary" phx-disable-with="Speichern…">Speichern</.button>
        </div>
      </.form>
    </Layouts.admin>
    """
  end
end
