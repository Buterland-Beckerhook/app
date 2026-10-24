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
     |> assign(:copy_warning, nil)
     |> apply_action(socket.assigns.live_action, params)}
  end

  defp apply_action(socket, :new, params) do
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

    # "Programmpunkt hinzufügen" on a festival: ?parent=<id> prefills the item with the
    # festival, its calendar, its first day and its location.
    event =
      case festival_for_new_item(user, params["parent"]) do
        nil ->
          event

        festival ->
          %{
            event
            | parent_id: festival.id,
              calendar: festival.calendar,
              location_id: festival.location_id,
              starts_at: Event.festival_opens(festival)
          }
      end

    socket
    |> assign(page_title: "Neuer Termin", event: event)
    |> assign_programme(event)
    |> assign_form(Calendar.change_event(event))
  end

  defp apply_action(socket, :edit, %{"id" => id}) do
    event = Calendar.get_event!(id)

    if Authz.can_edit_event?(socket.assigns.current_scope.user, event) do
      socket
      |> assign(page_title: "Termin bearbeiten", event: event)
      |> assign_programme(event)
      |> assign_form(Calendar.change_event(event))
    else
      socket
      |> put_flash(:error, "Kein Zugriff auf diesen Termin.")
      |> push_navigate(to: ~p"/admin/termine")
    end
  end

  defp festival_for_new_item(_user, id) when id in [nil, ""], do: nil

  defp festival_for_new_item(user, id) do
    with {:ok, uuid} <- Ecto.UUID.cast(id),
         %Event{parent_id: nil} = festival <- Bbh.Repo.get(Event, uuid),
         true <- Event.festival?(festival) and Authz.can_edit_event?(user, festival) do
      festival
    else
      _ -> nil
    end
  end

  # Festival context for the form: the festivals it may join ("Gehört zu"), and — for
  # a festival — its programme and earlier programmes to copy.
  defp assign_programme(socket, event) do
    user = socket.assigns.current_scope.user
    persisted? = not is_nil(event.id)
    programme = if persisted?, do: Calendar.list_children(event), else: []
    festival? = persisted? and is_nil(event.parent_id) and Event.festival?(event)

    socket
    |> assign(
      :festival_options,
      Calendar.festival_options(user, event.starts_at || Bbh.Time.now(), event.id)
    )
    |> assign(:parent, event.parent_id && Bbh.Repo.get(Event, event.parent_id))
    |> assign(:programme, programme)
    |> assign(:festival?, festival?)
    |> assign(
      :programme_sources,
      if(festival? and programme == [], do: Calendar.programme_sources(event), else: [])
    )
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

    if Authz.can_manage_calendar?(user, effective_calendar(params)) do
      save(socket, socket.assigns.live_action, params)
    else
      {:noreply, put_flash(socket, :error, "Für diesen Kalender fehlt die Berechtigung.")}
    end
  end

  # Copy an earlier festival's programme into this (programme-less) festival. When the
  # weekdays differ the shifted items land on other weekdays, so that needs a second,
  # explicit confirmation.
  def handle_event("copy-programme", %{"source" => source_id} = params, socket) do
    festival = socket.assigns.event
    source = Enum.find(socket.assigns.programme_sources, &(&1.id == source_id))

    cond do
      is_nil(source) or socket.assigns.programme != [] ->
        {:noreply, put_flash(socket, :error, "Programm kann nicht übernommen werden.")}

      not Authz.can_edit_event?(socket.assigns.current_scope.user, festival) ->
        {:noreply, put_flash(socket, :error, "Keine Berechtigung.")}

      not same_weekday?(source, festival) and params["confirm_weekday"] != "true" ->
        {:noreply,
         assign(socket, :copy_warning, %{
           source_id: source.id,
           text:
             "#{source.title} begann an einem anderen Wochentag – die Programmpunkte " <>
               "landen dadurch auf anderen Wochentagen. Trotzdem übernehmen?"
         })}

      true ->
        case Calendar.copy_programme(source, festival) do
          {:ok, items} ->
            {:noreply,
             socket
             |> assign(:copy_warning, nil)
             |> assign_programme(festival)
             |> put_flash(
               :info,
               "#{length(items)} Programmpunkte als Entwurf übernommen – bitte prüfen und veröffentlichen."
             )}

          {:error, title, changeset} ->
            {:noreply,
             socket
             |> assign(:copy_warning, nil)
             |> put_flash(:error, "„#{title}“ passt nicht ins Fest: #{first_error(changeset)}")}
        end
    end
  end

  def handle_event("copy-programme-cancel", _params, socket),
    do: {:noreply, assign(socket, :copy_warning, nil)}

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
        {:noreply,
         socket |> put_flash(:info, "Termin erstellt.") |> push_navigate(to: after_save(event))}

      {:error, changeset} ->
        {:noreply, assign_form(socket, changeset)}
    end
  end

  defp save(socket, :edit, params) do
    case Calendar.update_event(socket.assigns.event, params) do
      {:ok, event} ->
        {:noreply,
         socket
         |> put_flash(:info, "Termin gespeichert.")
         |> push_navigate(to: after_save(event))}

      {:error, changeset} ->
        {:noreply, assign_form(socket, changeset)}
    end
  end

  # No push from here: the "Neuer Termin" push is bundled by the cron
  # (Bbh.Workers.EventPublishNotifier) once publishing has settled.

  # A programme item goes back to its festival's programme, everything else to the list.
  defp after_save(%Event{parent_id: nil}), do: ~p"/admin/termine"
  defp after_save(%Event{parent_id: parent_id}), do: ~p"/admin/termine/#{parent_id}/bearbeiten"

  # The calendar a save lands in: an item's comes from its festival (the changeset
  # copies it), whatever the — hidden — field says.
  defp effective_calendar(%{"parent_id" => parent_id} = params) when parent_id not in [nil, ""] do
    case Ecto.UUID.cast(parent_id) do
      {:ok, uuid} ->
        case Bbh.Repo.get(Event, uuid) do
          %Event{calendar: calendar} -> calendar
          nil -> params["calendar"]
        end

      :error ->
        params["calendar"]
    end
  end

  defp effective_calendar(params), do: params["calendar"]

  defp same_weekday?(a, b), do: Date.day_of_week(a.starts_at) == Date.day_of_week(b.starts_at)

  defp first_error(%Ecto.Changeset{errors: [{field, {message, _}} | _]}),
    do: "#{field} #{message}"

  defp first_error(_changeset), do: "ungültig"

  defp assign_form(socket, changeset), do: assign(socket, :form, to_form(changeset, as: "event"))

  # datetime-local strings → ISO8601 UTC; blank select values → nil.
  defp normalize(params) do
    params
    |> Map.update("starts_at", nil, &parse_dt/1)
    |> Map.update("ends_at", nil, &parse_dt/1)
    |> normalize_reminders()
    |> blank_to_nil("calendar")
    |> blank_to_nil("location_id")
    |> blank_to_nil("parent_id")
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
        <%!-- A festival with a programme cannot itself belong to one. --%>
        <div :if={@programme == []}>
          <.input
            field={@form[:parent_id]}
            type="select"
            label="Gehört zu"
            prompt="— eigenständiger Termin —"
            options={@festival_options}
          />
          <p :if={item_form?(@form) && @parent} class="mt-1 text-sm">
            Programmpunkt von
            <.link navigate={~p"/admin/termine/#{@parent.id}/bearbeiten"} class="link link-primary">
              {@parent.title}
            </.link>
            – Kalender, Countdown und Ankündigung kommen vom Fest.
          </p>
        </div>
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
          :if={!item_form?(@form)}
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
          :if={!item_form?(@form)}
          field={@form[:calendar]}
          type="select"
          label="Kalender"
          options={@calendar_options}
        />
        <.input
          :if={public_calendar?(@form) && !item_form?(@form)}
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
          :if={public_calendar?(@form) && !item_form?(@form)}
          field={@form[:show_countdown]}
          type="checkbox"
          label="Countdown anzeigen"
        />
        <.input
          :if={public_calendar?(@form) && !item_form?(@form)}
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

          <%!-- Required so dropping the last reminder still sends a reminders_drop param
                (otherwise Ecto keeps it). See phoenix_component inputs_for docs. --%>
          <input type="hidden" name="event[reminders_drop][]" />

          <label class="mt-1 inline-block cursor-pointer text-sm font-medium text-primary hover:underline">
            <input type="checkbox" name="event[reminders_sort][]" value="new" class="hidden" />
            + Erinnerung hinzufügen
          </label>
        </fieldset>

        <div class="flex gap-2">
          <.button variant="primary" phx-disable-with="Speichern…">Speichern</.button>
          <.button navigate={~p"/admin/termine"}>Abbrechen</.button>
        </div>
      </.form>

      <section :if={@festival?} id="programme" class="mt-10">
        <.header>
          Programm
          <:subtitle>
            Programmpunkte erscheinen nur auf der Festseite (und im Kalender-Export), nie
            einzeln in der Terminliste, und lösen keine „Neuer Termin“-Benachrichtigung aus.
          </:subtitle>
          <:actions>
            <.button navigate={~p"/admin/termine/neu?parent=#{@event.id}"}>
              Programmpunkt hinzufügen
            </.button>
          </:actions>
        </.header>

        <.table :if={@programme != []} id="programme-items" rows={@programme}>
          <:col :let={item} label="Zeit">
            <span class="whitespace-nowrap tabular-nums">
              {BbhWeb.EventHTML.item_when(item)}
            </span>
          </:col>
          <:col :let={item} label="Titel"><span class="font-medium">{item.title}</span></:col>
          <:col :let={item} label="Status"><.status_badge status={item.status} /></:col>
          <:action :let={item}>
            <.link
              navigate={~p"/admin/termine/#{item.id}/bearbeiten"}
              class="link link-primary"
              title="Bearbeiten"
              aria-label="Bearbeiten"
            >
              <.icon name="hero-pencil-square" class="size-5" />
            </.link>
          </:action>
        </.table>

        <div
          :if={@programme == [] && @programme_sources != []}
          class="mt-4 rounded-box border border-base-300 p-4"
        >
          <p class="text-sm font-medium">Programm aus einem früheren Fest übernehmen</p>
          <p class="mt-1 text-sm text-base-content/60">
            Kopiert alle Programmpunkte als <strong>Entwurf</strong>, um die Tage zwischen den
            Festen verschoben – Uhrzeiten, Orte und Texte bleiben, Erinnerungen nicht.
          </p>
          <form
            :if={!@copy_warning}
            id="copy-programme-form"
            phx-submit="copy-programme"
            class="mt-3 flex flex-wrap items-center gap-2"
          >
            <select name="source" class="select select-sm select-bordered" aria-label="Fest">
              <option :for={src <- @programme_sources} value={src.id}>
                {src.title} ({de_date(src.starts_at)})
              </option>
            </select>
            <.button phx-disable-with="Übernehme…">Übernehmen</.button>
          </form>
          <form
            :if={@copy_warning}
            id="copy-programme-confirm"
            phx-submit="copy-programme"
            class="mt-3 space-y-2"
          >
            <p class="text-sm text-warning">{@copy_warning.text}</p>
            <input type="hidden" name="source" value={@copy_warning.source_id} />
            <input type="hidden" name="confirm_weekday" value="true" />
            <div class="flex gap-2">
              <.button variant="primary">Trotzdem übernehmen</.button>
              <button type="button" class="btn" phx-click="copy-programme-cancel">
                Abbrechen
              </button>
            </div>
          </form>
        </div>
      </section>

      <.danger_zone
        :if={@live_action == :edit and Authz.can_delete_event?(@current_scope.user, @event)}
        confirm_value={@event.slug}
      >
        Der Termin „{@event.title}" wird dauerhaft gelöscht. Dies kann nicht rückgängig gemacht werden.
        <strong :if={@programme != []}>
          Löscht auch {BbhWeb.EventHTML.programme_count(length(@programme))}.
        </strong>
      </.danger_zone>
      <.live_component module={BbhWeb.Admin.MediaPicker} id="media-picker" />
    </Layouts.admin>
    """
  end

  defp statuses, do: @statuses

  # A programme item (a festival chosen under "Gehört zu"): calendar, all-day,
  # countdown and announcement come from the festival, so the form hides them.
  defp item_form?(form), do: form[:parent_id].value not in [nil, ""]

  # Public events (no internal calendar) get the public-facing options; internal
  # ones don't — they only surface via a shared .ics feed.
  defp public_calendar?(form) do
    case form[:calendar].value do
      cal when cal in [nil, ""] -> true
      _internal -> false
    end
  end
end
