defmodule BbhWeb.Admin.EventLive.Form do
  use BbhWeb, :live_view

  alias Bbh.Calendar
  alias Bbh.Calendar.Event

  @statuses [{"Entwurf", "draft"}, {"Veröffentlicht", "published"}, {"Abgesagt", "canceled"}]
  @calendars [
    {"Öffentlich", ""},
    {"Vorstand", "vorstand"},
    {"Offiziere", "offiziere"},
    {"Jungschützen", "jungschuetzen"},
    {"Kinderfest", "kinderfest"}
  ]

  @impl true
  def mount(params, _session, socket) do
    {:ok,
     socket
     |> assign(:location_options, Calendar.location_options())
     |> apply_action(socket.assigns.live_action, params)}
  end

  defp apply_action(socket, :new, _params) do
    event = %Event{status: "draft", announce: true, enable_ical: true, all_day: false}

    socket
    |> assign(page_title: "Neuer Termin", event: event)
    |> assign_form(Calendar.change_event(event))
  end

  defp apply_action(socket, :edit, %{"id" => id}) do
    event = Calendar.get_event!(id)

    socket
    |> assign(page_title: "Termin bearbeiten", event: event)
    |> assign_form(Calendar.change_event(event))
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
    save(socket, socket.assigns.live_action, normalize(params))
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
          <.input field={@form[:starts_at]} type="datetime-local" label="Beginn" required />
          <.input field={@form[:ends_at]} type="datetime-local" label="Ende" />
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
          options={calendars()}
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
    </Layouts.admin>
    """
  end

  defp statuses, do: @statuses
  defp calendars, do: @calendars
end
