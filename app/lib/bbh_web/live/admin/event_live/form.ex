defmodule BbhWeb.Admin.EventLive.Form do
  use BbhWeb, :live_view

  alias Bbh.Calendar
  alias Bbh.Calendar.Event
  alias BbhWeb.Authz

  @statuses [{"Entwurf", "draft"}, {"Veröffentlicht", "published"}, {"Abgesagt", "canceled"}]

  @impl true
  def mount(params, _session, socket) do
    user = socket.assigns.current_scope.user

    {:ok,
     socket
     |> assign(:location_options, Calendar.location_options())
     |> assign(:calendar_options, Authz.assignable_calendar_options(user))
     |> apply_action(socket.assigns.live_action, params)}
  end

  defp apply_action(socket, :new, _params) do
    user = socket.assigns.current_scope.user

    default_cal =
      if Authz.can_manage_calendar?(user, nil), do: nil, else: List.first(user.calendars)

    event = %Event{
      status: "draft",
      announce: true,
      enable_ical: true,
      all_day: false,
      calendar: default_cal,
      reminders: []
    }

    socket
    |> assign(page_title: "Neuer Termin", event: event)
    |> assign_form(Calendar.change_event(event))
  end

  defp apply_action(socket, :edit, %{"id" => id}) do
    event = Calendar.get_event!(id)

    if Authz.can_edit_event?(socket.assigns.current_scope.user, event) do
      socket
      |> assign(page_title: "Termin bearbeiten", event: event)
      |> assign_form(Calendar.change_event(event))
    else
      socket
      |> put_flash(:error, "Kein Zugriff auf diesen Termin.")
      |> push_navigate(to: ~p"/admin/termine")
    end
  end

  @impl true
  def handle_event("validate", %{"event" => params}, socket) do
    changeset =
      socket.assigns.event
      |> Calendar.change_event(normalize(params))
      |> Map.put(:action, :validate)

    {:noreply, assign_form(socket, changeset)}
  end

  def handle_event("save", %{"event" => params}, socket) do
    params = normalize(params)
    user = socket.assigns.current_scope.user

    if Authz.can_manage_calendar?(user, params["calendar"]) do
      save(socket, socket.assigns.live_action, params)
    else
      {:noreply, put_flash(socket, :error, "Für diesen Kalender fehlt die Berechtigung.")}
    end
  end

  def handle_event("delete", %{"confirm" => confirm}, socket) do
    event = socket.assigns.event

    cond do
      not Authz.can_delete_event?(socket.assigns.current_scope.user, event) ->
        {:noreply, put_flash(socket, :error, "Keine Berechtigung zum Löschen.")}

      confirm == event.slug ->
        {:ok, _} = Calendar.delete_event(event)

        {:noreply,
         socket |> put_flash(:info, "Termin gelöscht.") |> push_navigate(to: ~p"/admin/termine")}

      true ->
        {:noreply, put_flash(socket, :error, "Der eingegebene Wert stimmt nicht überein.")}
    end
  end

  defp save(socket, :new, params) do
    case Calendar.create_event(params) do
      {:ok, event} ->
        maybe_notify(nil, event)

        {:noreply,
         socket |> put_flash(:info, "Termin erstellt.") |> push_navigate(to: ~p"/admin/termine")}

      {:error, changeset} ->
        {:noreply, assign_form(socket, changeset)}
    end
  end

  defp save(socket, :edit, params) do
    old_status = socket.assigns.event.status

    case Calendar.update_event(socket.assigns.event, params) do
      {:ok, event} ->
        maybe_notify(old_status, event)

        {:noreply,
         socket
         |> put_flash(:info, "Termin gespeichert.")
         |> push_navigate(to: ~p"/admin/termine")}

      {:error, changeset} ->
        {:noreply, assign_form(socket, changeset)}
    end
  end

  # Notify subscribers the first time a public event becomes published. Routed
  # through EventPublishNotifier so it marks the event (no repeat) and honours
  # quiet hours — anything held back overnight is delivered by the cron tick.
  defp maybe_notify(
         old_status,
         %Event{status: "published", announce: true, calendar: nil} = event
       )
       when old_status != "published" do
    Bbh.Notifications.dispatch(fn -> Bbh.Workers.EventPublishNotifier.notify(event) end)
  end

  defp maybe_notify(_old_status, _event), do: :ok

  defp assign_form(socket, changeset), do: assign(socket, :form, to_form(changeset, as: "event"))

  # datetime-local strings → ISO8601 UTC; blank select values → nil.
  defp normalize(params) do
    params
    |> Map.update("starts_at", nil, &parse_dt/1)
    |> Map.update("ends_at", nil, &parse_dt/1)
    |> normalize_reminders()
    |> blank_to_nil("calendar")
    |> blank_to_nil("location_id")
  end

  # Reminders are nested (event[reminders][<idx>][...]); their absolute scheduled_at
  # arrives as a datetime-local string and needs the same ISO8601 normalization.
  defp normalize_reminders(%{"reminders" => reminders} = params) when is_map(reminders) do
    normalized =
      Map.new(reminders, fn {idx, reminder} ->
        {idx, Map.update(reminder, "scheduled_at", nil, &parse_dt/1)}
      end)

    Map.put(params, "reminders", normalized)
  end

  defp normalize_reminders(params), do: params

  defp parse_dt(v) when v in [nil, ""], do: nil

  defp parse_dt(v) when is_binary(v) do
    cond do
      Regex.match?(~r/^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}$/, v) -> v <> ":00Z"
      Regex.match?(~r/^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}$/, v) -> v <> "Z"
      # Date-only (all-day picker) → midnight.
      Regex.match?(~r/^\d{4}-\d{2}-\d{2}$/, v) -> v <> "T00:00:00Z"
      true -> v
    end
  end

  defp blank_to_nil(map, key) do
    Map.update(map, key, nil, fn v -> if v in ["", nil], do: nil, else: v end)
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.admin flash={@flash} current_scope={@current_scope} active={:events}>
      <.header>{@page_title}</.header>

      <.form
        for={@form}
        id="event-form"
        phx-change="validate"
        phx-submit="save"
        class="mt-6 space-y-4"
      >
        <.input field={@form[:title]} label="Titel" required phx-hook="SlugFromTitle" />
        <.input field={@form[:slug]} label="Slug" required />
        <.input field={@form[:status]} type="select" label="Status" options={statuses()} />
        <div class="grid gap-4 sm:grid-cols-2">
          <%!-- The start keeps its time even for all-day events: iCal exports only the
                date, but the countdown still targets the entered start time. --%>
          <.datetime_field field={@form[:starts_at]} label="Beginn" required />
          <.datetime_field
            field={@form[:ends_at]}
            label="Ende"
            all_day_selector="[name='event[all_day]']"
          />
        </div>
        <.input
          field={@form[:all_day]}
          type="checkbox"
          label="Ganztägig (im Kalender-Export nur das Datum)"
        />
        <.input
          field={@form[:location_id]}
          type="select"
          label="Ort"
          prompt="— kein Ort —"
          options={@location_options}
        />
        <.input
          field={@form[:calendar]}
          type="select"
          label="Kalender"
          options={@calendar_options}
        />
        <.input
          :if={public_calendar?(@form)}
          field={@form[:announce]}
          type="checkbox"
          label="Öffentlich ankündigen"
        />
        <.input
          :if={public_calendar?(@form)}
          field={@form[:enable_ical]}
          type="checkbox"
          label="iCal-Export aktivieren"
        />
        <.input
          :if={public_calendar?(@form)}
          field={@form[:show_countdown]}
          type="checkbox"
          label="Countdown anzeigen"
        />
        <.input
          :if={public_calendar?(@form)}
          field={@form[:countdown_lead_days]}
          type="number"
          min="0"
          label="Countdown ab (Tage vor Beginn)"
        />
        <.input field={@form[:cancel_reason]} label="Grund bei Absage" />
        <.rich_text field={@form[:body]} label="Beschreibung" />

        <fieldset :if={public_calendar?(@form)} class="rounded-box border border-base-300 p-4">
          <legend class="px-1 text-sm font-medium">Erinnerungen (Push)</legend>
          <p class="mb-3 text-sm text-base-content/60">
            Benachrichtigt Abonnenten – entweder eine Anzahl Tage vor Beginn <strong>oder</strong>
            zu einem festen Zeitpunkt. Ohne eigenen Text wird der Titel gesendet; die Nachricht
            verlinkt immer auf den Termin.
          </p>

          <.inputs_for :let={rf} field={@form[:reminders]}>
            <input type="hidden" name="event[reminders_sort][]" value={rf.index} />
            <div class="mb-3 flex flex-wrap items-start gap-3">
              <div class="w-28">
                <.input field={rf[:lead_days]} type="number" min="0" label="Tage vorher" />
              </div>
              <span class="mt-8 text-sm text-base-content/50">oder</span>
              <div class="w-56">
                <.datetime_field field={rf[:scheduled_at]} label="Fester Zeitpunkt" />
              </div>
              <div class="min-w-48 flex-1">
                <.input field={rf[:text]} label="Nachricht (optional)" />
              </div>
              <label class="mt-8 cursor-pointer text-sm text-error hover:underline">
                <input type="checkbox" name="event[reminders_drop][]" value={rf.index} class="hidden" />
                Entfernen
              </label>
            </div>
          </.inputs_for>

          <label class="mt-1 inline-block cursor-pointer text-sm font-medium text-primary hover:underline">
            <input type="checkbox" name="event[reminders_sort][]" class="hidden" />
            + Erinnerung hinzufügen
          </label>
        </fieldset>

        <div class="flex gap-2">
          <.button variant="primary" phx-disable-with="Speichern…">Speichern</.button>
          <.button navigate={~p"/admin/termine"}>Abbrechen</.button>
        </div>
      </.form>

      <.danger_zone
        :if={@live_action == :edit and Authz.can_delete_event?(@current_scope.user, @event)}
        confirm_value={@event.slug}
      >
        Der Termin „{@event.title}" wird dauerhaft gelöscht. Dies kann nicht rückgängig gemacht werden.
      </.danger_zone>
      <.live_component module={BbhWeb.Admin.MediaPicker} id="media-picker" />
    </Layouts.admin>
    """
  end

  defp statuses, do: @statuses

  # Public events (no internal calendar) get the public-facing options; internal
  # ones don't — they only surface via a shared .ics feed.
  defp public_calendar?(form) do
    case form[:calendar].value do
      cal when cal in [nil, ""] -> true
      _internal -> false
    end
  end
end
