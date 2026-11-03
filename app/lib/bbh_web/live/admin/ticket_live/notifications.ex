defmodule BbhWeb.Admin.TicketLive.Notifications do
  @moduledoc """
  A user's own Postfach notification settings: how often, over which channel, and the
  devices that get pushes. Quiet hours are site-wide and only shown here. In the
  `:admin_tickets` live_session, because it concerns exactly who may enter the Postfach.
  """
  use BbhWeb, :live_view

  alias Bbh.Accounts.User
  alias Bbh.Notifications
  alias Bbh.Settings
  alias Bbh.Tickets.Alerts

  @interval_labels %{
    2 => "Sofort (innerhalb von 2 Minuten)",
    15 => "Alle 15 Minuten",
    60 => "Stündlich",
    120 => "Alle 2 Stunden",
    240 => "Alle 4 Stunden",
    480 => "Alle 8 Stunden",
    720 => "Alle 12 Stunden",
    1440 => "Einmal am Tag"
  }

  # Beyond this the list of times says more than the name does.
  @list_times_from 240

  @channel_labels %{"mail" => "E-Mail", "push" => "Push", "both" => "E-Mail und Push"}

  @impl true
  def mount(_params, _session, socket) do
    user = socket.assigns.current_scope.user
    settings = Settings.get()

    {:ok,
     socket
     |> assign(
       page_title: "Benachrichtigungen",
       user: user,
       interval_options:
         for(i <- User.ticket_notify_intervals(), do: {interval_label(i, settings), i}),
       channel_options: for(c <- User.ticket_notify_channels(), do: {@channel_labels[c], c}),
       settings: settings,
       browser_kind: nil,
       browser_endpoint: nil
     )
     |> assign_form(Alerts.change_preferences(user))
     |> load_devices()}
  end

  @impl true
  def handle_event("save", %{"user" => params}, socket) do
    case Alerts.update_preferences(socket.assigns.user, params) do
      {:ok, user} ->
        {:noreply,
         socket
         |> assign(user: user)
         |> assign_form(Alerts.change_preferences(user))
         |> put_flash(:info, "Einstellungen gespeichert.")}

      {:error, changeset} ->
        {:noreply, assign_form(socket, changeset)}
    end
  end

  # From the PostfachPush hook. The endpoint is only compared, never rendered.
  def handle_event("browser_state", %{"kind" => kind} = params, socket) do
    endpoint = if is_binary(params["endpoint"]), do: params["endpoint"]
    {:noreply, assign(socket, browser_kind: kind, browser_endpoint: endpoint)}
  end

  def handle_event("device_linked", _params, socket) do
    {:noreply,
     socket
     |> load_devices()
     |> put_flash(:info, "Dieses Gerät ist jetzt eingerichtet.")}
  end

  def handle_event("device_link_failed", _params, socket) do
    {:noreply, put_flash(socket, :error, "Das Gerät konnte nicht eingerichtet werden.")}
  end

  def handle_event("unlink", %{"id" => id}, socket) do
    Notifications.unlink_device(socket.assigns.user, id)
    {:noreply, socket |> load_devices() |> put_flash(:info, "Gerät entfernt.")}
  end

  def handle_event("test_push", _params, socket) do
    user = socket.assigns.user
    Notifications.dispatch(fn -> Alerts.test_push(user) end)
    {:noreply, put_flash(socket, :info, "Testnachricht wird an deine Geräte gesendet.")}
  end

  defp interval_label(minutes, _settings) when minutes < @list_times_from,
    do: @interval_labels[minutes]

  defp interval_label(minutes, settings) do
    times = minutes |> Alerts.slots(settings) |> Enum.map_join(", ", &slot_time/1)
    "#{@interval_labels[minutes]} (#{times} Uhr)"
  end

  defp slot_time(slot) when rem(slot, 60) == 0, do: "#{div(slot, 60)}"

  defp slot_time(slot) do
    minutes = slot |> rem(60) |> Integer.to_string() |> String.pad_leading(2, "0")
    "#{div(slot, 60)}:#{minutes}"
  end

  defp assign_form(socket, changeset), do: assign(socket, form: to_form(changeset))

  defp load_devices(socket) do
    assign(socket, devices: Notifications.list_user_devices(socket.assigns.user))
  end

  defp this_device?(device, endpoint), do: device.endpoint == endpoint

  defp linked?(devices, endpoint), do: Enum.any?(devices, &this_device?(&1, endpoint))

  defp quiet_hours(%{quiet_hours_enabled: true, quiet_hours_start: start, quiet_hours_end: fin})
       when start != fin,
       do: "Zwischen #{start}:00 und #{fin}:00 Uhr"

  defp quiet_hours(_settings), do: nil

  defp local(dt) do
    dt |> DateTime.shift_zone!(Bbh.Time.time_zone()) |> BbhWeb.Format.de_short_datetime()
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.admin flash={@flash} current_scope={@current_scope} active={:tickets}>
      <.header>
        Benachrichtigungen
        <:subtitle>
          Wie oft und auf welchem Weg dich das Postfach über Neues informiert.
        </:subtitle>
        <:actions>
          <.button navigate={~p"/admin/postfach"}>Zum Postfach</.button>
        </:actions>
      </.header>

      <.form for={@form} id="notification-form" phx-submit="save" class="mt-6 max-w-lg space-y-4">
        <.input
          field={@form[:ticket_notify_interval_minutes]}
          type="select"
          label="Neue Anfragen und Antworten"
          options={@interval_options}
        />
        <p class="text-sm text-base-content/60">
          Was bis dahin eingeht, kommt gesammelt in einer Nachricht, zusammen mit den
          täglichen Erinnerungen an Wartendes. Zugewiesene Anfragen kommen immer gleich.
        </p>
        <.input
          field={@form[:ticket_notify_channel]}
          type="select"
          label="Benachrichtigen per"
          options={@channel_options}
        />
        <.button variant="primary" phx-disable-with="Speichern…">Speichern</.button>
      </.form>

      <section id="quiet-hours" class="mt-8 max-w-lg">
        <h2 class="font-semibold">Ruhezeit</h2>
        <p class="mt-1 text-sm">
          {quiet_hours(@settings) || "Keine Ruhezeit eingestellt."}
        </p>
        <p :if={quiet_hours(@settings)} class="text-sm text-base-content/60">
          Gilt für alle und für E-Mail wie Push. Was in dieser Zeit eingeht, kommt danach.
          Die Website-Einstellungen legen sie fest.
        </p>
      </section>

      <section id="push-devices" phx-hook="PostfachPush" class="mt-8 max-w-lg">
        <h2 class="font-semibold">Geräte für Push</h2>
        <p class="mt-1 text-sm text-base-content/60">
          Push geht an alle hier aufgeführten Geräte. Jeder Browser muss einmal auf dem Gerät
          selbst eingerichtet werden. Ohne erreichbares Gerät kommt die Nachricht per E-Mail.
        </p>

        <div
          :if={@form[:ticket_notify_channel].value != "mail" and @devices == []}
          id="no-devices"
          class="alert alert-warning mt-4"
        >
          Noch kein Gerät eingerichtet – bis dahin benachrichtigen wir dich per E-Mail.
        </div>

        <ul :if={@devices != []} id="device-list" class="mt-4 divide-y divide-base-300">
          <li
            :for={d <- @devices}
            id={"device-#{d.id}"}
            class="flex items-center justify-between gap-3 py-3"
          >
            <div class="min-w-0">
              <p class="truncate font-medium">
                {d.label || d.device || "Unbekanntes Gerät"}
                <span
                  :if={this_device?(d, @browser_endpoint)}
                  class="badge badge-sm badge-success ml-1"
                >
                  Dieses Gerät
                </span>
              </p>
              <p class="text-xs text-base-content/60">
                <span :if={d.label && d.device}>{d.device} · </span>
                Eingerichtet {local(d.inserted_at)}
                <span :if={d.last_used}>· zuletzt genutzt {local(d.last_used)}</span>
                <span :if={d.error_count > 0} class="text-error">
                  · {d.error_count} fehlgeschlagene Zustellungen
                </span>
              </p>
            </div>
            <button
              type="button"
              class="btn btn-sm btn-outline btn-error shrink-0"
              phx-click="unlink"
              phx-value-id={d.id}
              data-confirm="Dieses Gerät entfernen?"
            >
              Entfernen
            </button>
          </li>
        </ul>

        <div class="mt-4 flex flex-wrap items-center gap-2">
          <button
            :if={@browser_kind in ["on", "off"] and not linked?(@devices, @browser_endpoint)}
            id="link-device"
            type="button"
            class="btn btn-primary btn-sm"
            data-push-link
          >
            Auf diesem Gerät einrichten
          </button>
          <button
            :if={@devices != []}
            id="test-push"
            type="button"
            class="btn btn-sm"
            phx-click="test_push"
          >
            Testnachricht senden
          </button>
        </div>

        <p :if={@browser_kind == "install"} class="mt-3 text-sm">
          Auf iPhone und iPad gibt es Push nur, wenn die Seite installiert ist: im Teilen-Menü
          „Zum Home-Bildschirm“ wählen und von dort öffnen.
        </p>
        <p :if={@browser_kind == "unsupported"} class="mt-3 text-sm">
          Dieser Browser unterstützt keine Push-Benachrichtigungen.
        </p>
        <p :if={@browser_kind == "denied"} class="mt-3 text-sm">
          Benachrichtigungen sind für diese Seite im Browser blockiert. Bitte in den
          Website-Einstellungen des Browsers erlauben.
        </p>
      </section>
    </Layouts.admin>
    """
  end
end
