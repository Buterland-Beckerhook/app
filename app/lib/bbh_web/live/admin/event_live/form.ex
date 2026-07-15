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
      calendar: default_cal
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

  # Notify subscribers the first time a public event becomes published.
  defp maybe_notify(
         old_status,
         %Event{status: "published", announce: true, calendar: nil} = event
       )
       when old_status != "published" do
    url = url(~p"/termine/#{event.year}/#{event.slug}")

    Task.Supervisor.start_child(Bbh.TaskSupervisor, fn ->
      Bbh.Notifications.notify("termine", %{title: "Neuer Termin", body: event.title, url: url})
    end)
  end

  defp maybe_notify(_old_status, _event), do: :ok

  defp assign_form(socket, changeset), do: assign(socket, :form, to_form(changeset, as: "event"))

  # datetime-local strings → ISO8601 UTC; blank select values → nil.
  defp normalize(params) do
    params
    |> Map.update("starts_at", nil, &parse_dt/1)
    |> Map.update("ends_at", nil, &parse_dt/1)
    |> blank_to_nil("calendar")
    |> blank_to_nil("location_id")
  end

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
        <.input field={@form[:title]} label="Titel" required />
        <.input field={@form[:slug]} label="Slug" required />
        <.input field={@form[:status]} type="select" label="Status" options={statuses()} />
        <div class="grid gap-4 sm:grid-cols-2">
          <.datetime_field field={@form[:starts_at]} label="Beginn" required />
          <.datetime_field field={@form[:ends_at]} label="Ende" />
        </div>
        <.input field={@form[:all_day]} type="checkbox" label="Ganztägig" />
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
        <.input field={@form[:announce]} type="checkbox" label="Öffentlich ankündigen" />
        <.input field={@form[:enable_ical]} type="checkbox" label="iCal-Export aktivieren" />
        <.input field={@form[:cancel_reason]} label="Grund bei Absage" />
        <.rich_text field={@form[:body]} label="Beschreibung" />

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
    </Layouts.admin>
    """
  end

  defp statuses, do: @statuses

  # A German-formatted date/time field backed by flatpickr (see the DatePicker JS hook).
  # The picker's injected DOM is protected with phx-update="ignore"; validation errors
  # render outside that wrapper so LiveView can still update them.
  attr :field, Phoenix.HTML.FormField, required: true
  attr :label, :string, required: true
  attr :required, :boolean, default: false

  defp datetime_field(assigns) do
    ~H"""
    <div>
      <label class="label mb-1" for={@field.id}>{@label}</label>
      <div id={"dp-#{@field.id}"} phx-update="ignore">
        <input
          type="text"
          id={@field.id}
          name={@field.name}
          value={dt_value(@field.value)}
          required={@required}
          autocomplete="off"
          phx-hook="DatePicker"
          data-all-day-selector="[name='event[all_day]']"
          class="input input-bordered w-full"
        />
      </div>
      <p
        :for={error <- @field.errors}
        class="mt-1.5 flex items-center gap-2 text-sm text-error"
      >
        <.icon name="hero-exclamation-circle" class="size-5" />
        {translate_error(error)}
      </p>
    </div>
    """
  end

  # Render a stored datetime as the "YYYY-MM-DDTHH:MM" flatpickr parses on init.
  defp dt_value(%{year: y, month: mo, day: d, hour: h, minute: mi}),
    do: "#{y}-#{pad(mo)}-#{pad(d)}T#{pad(h)}:#{pad(mi)}"

  defp dt_value(v) when is_binary(v), do: v
  defp dt_value(_), do: ""

  defp pad(n), do: String.pad_leading(Integer.to_string(n), 2, "0")
end
