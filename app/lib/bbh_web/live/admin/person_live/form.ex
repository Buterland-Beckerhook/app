defmodule BbhWeb.Admin.PersonLive.Form do
  use BbhWeb, :live_view

  alias Bbh.Club
  alias Bbh.Club.Person

  @impl true
  def mount(params, _session, socket) do
    {:ok, apply_action(socket, socket.assigns.live_action, params)}
  end

  defp apply_action(socket, :new, _params) do
    person = %Person{role: "mitglied", sort_order: 0}

    socket
    |> assign(page_title: "Neue Person", person: person, portrait: nil)
    |> assign_form(Club.change_person(person))
  end

  defp apply_action(socket, :edit, %{"id" => id}) do
    person = Club.get_person!(id)

    socket
    |> assign(page_title: "Person bearbeiten", person: person, portrait: person.portrait)
    |> assign_form(Club.change_person(person))
  end

  @impl true
  def handle_event("validate", %{"person" => params}, socket) do
    changeset =
      socket.assigns.person |> Club.change_person(params) |> Map.put(:action, :validate)

    {:noreply, assign_form(socket, changeset)}
  end

  def handle_event("save", %{"person" => params}, socket) do
    save(socket, socket.assigns.live_action, params)
  end

  def handle_event("clear_portrait", _params, socket) do
    {:noreply, put_portrait(socket, nil)}
  end

  def handle_event("delete", %{"confirm" => confirm}, socket) do
    person = socket.assigns.person

    cond do
      not BbhWeb.Authz.can_delete?(socket.assigns.current_scope.user, person) ->
        {:noreply, put_flash(socket, :error, "Keine Berechtigung zum Löschen.")}

      confirm == person.name ->
        {:ok, _} = Club.delete_person(person)

        {:noreply,
         socket |> put_flash(:info, "Person gelöscht.") |> push_navigate(to: ~p"/admin/personen")}

      true ->
        {:noreply, put_flash(socket, :error, "Der eingegebene Wert stimmt nicht überein.")}
    end
  end

  defp save(socket, :new, params) do
    case Club.create_person(params) do
      {:ok, _} ->
        {:noreply,
         socket |> put_flash(:info, "Person erstellt.") |> push_navigate(to: ~p"/admin/personen")}

      {:error, changeset} ->
        {:noreply, assign_form(socket, changeset)}
    end
  end

  defp save(socket, :edit, params) do
    case Club.update_person(socket.assigns.person, params) do
      {:ok, _} ->
        {:noreply,
         socket
         |> put_flash(:info, "Person gespeichert.")
         |> push_navigate(to: ~p"/admin/personen")}

      {:error, changeset} ->
        {:noreply, assign_form(socket, changeset)}
    end
  end

  # A pick from the shared media picker (BbhWeb.Admin.MediaPicker). Unlike the page form,
  # which writes the choice straight to the block row, the portrait goes into the changeset
  # and is saved with the rest of the form — on :new there is no row to write to yet.
  #
  # `get_upload/1`, not `get_upload!/1`: the picture can be gone by the time the pick lands
  # (deleted in another tab — nothing refuses that, since the portrait is not in use yet),
  # and a raise here would take the whole form down along with everything typed into it.
  # Same stance as the page form's block lookup.
  @impl true
  def handle_info({:media_selected, %{"context" => "portrait"}, id}, socket) do
    case Bbh.Media.get_upload(id) do
      nil -> {:noreply, put_flash(socket, :error, "Dieses Bild existiert nicht mehr.")}
      upload -> {:noreply, put_portrait(socket, upload)}
    end
  end

  # Carries the upload struct rather than its id so `@portrait` (the thumbnail) and the
  # changeset's `portrait_id` cannot drift apart — both are written only here.
  defp put_portrait(socket, upload) do
    changeset =
      socket.assigns.form.source
      |> Ecto.Changeset.put_change(:portrait_id, upload && upload.id)
      |> Map.put(:action, :validate)

    socket
    |> assign(:portrait, upload)
    |> assign_form(changeset)
  end

  defp assign_form(socket, changeset), do: assign(socket, :form, to_form(changeset, as: "person"))

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.admin flash={@flash} current_scope={@current_scope} active={:people}>
      <.header>{@page_title}</.header>

      <.form
        for={@form}
        id="person-form"
        phx-change="validate"
        phx-submit="save"
        class="mt-6 space-y-4"
      >
        <.input field={@form[:name]} label="Name" required />
        <.input field={@form[:role]} type="select" label="Rolle" options={Club.role_options()} />
        <.input field={@form[:email]} type="email" label="E-Mail" />
        <.input field={@form[:honorary_member]} type="checkbox" label="Ehrenmitglied" />
        <div class="grid grid-cols-2 gap-4">
          <.input field={@form[:street]} label="Straße" />
          <.input field={@form[:city]} label="Ort" />
        </div>
        <div class="grid grid-cols-2 gap-4">
          <.input field={@form[:year_start]} type="number" label="Amt von (Jahr)" />
          <.input field={@form[:year_end]} type="number" label="Amt bis (Jahr)" />
        </div>
        <div class="grid grid-cols-2 gap-4">
          <.input field={@form[:birth_date]} label="Geboren" />
          <.input field={@form[:death_date]} label="Gestorben" />
        </div>
        <.input field={@form[:sort_order]} type="number" label="Sortierung" />
        <.portrait_field portrait={@portrait} field={@form[:portrait_id]} />
        <.rich_text field={@form[:biography]} label="Biografie" />

        <div class="flex gap-2">
          <.button variant="primary" phx-disable-with="Speichern…">Speichern</.button>
          <.button navigate={~p"/admin/personen"}>Abbrechen</.button>
        </div>
      </.form>

      <.danger_zone
        :if={@live_action == :edit and BbhWeb.Authz.can_delete?(@current_scope.user, @person)}
        confirm_value={@person.name}
      >
        Die Person „{@person.name}" wird dauerhaft gelöscht.
      </.danger_zone>
      <.live_component module={BbhWeb.Admin.MediaPicker} id="media-picker" />
    </Layouts.admin>
    """
  end

  # The portrait shown by the Personenliste's „Karten" style. The choice lives in the
  # form's changeset, so it needs a hidden input to survive the next phx-change; the
  # buttons are type="button" and therefore cannot submit the form they sit in.
  attr :portrait, :any, required: true
  attr :field, Phoenix.HTML.FormField, required: true

  defp portrait_field(assigns) do
    ~H"""
    <fieldset class="fieldset">
      <legend class="label mb-1">Portrait</legend>
      <input type="hidden" name={@field.name} value={@field.value} />
      <div class="flex items-center gap-3 rounded-box bg-base-200/50 p-3">
        <img
          :if={@portrait}
          src={media_url(@portrait, width: 160, height: 200)}
          alt={image_alt(@portrait)}
          class="aspect-[4/5] w-20 rounded object-cover"
        />
        <span
          :if={is_nil(@portrait)}
          class="flex aspect-[4/5] w-20 items-center justify-center rounded bg-base-300 text-xs text-base-content/60"
        >
          Kein Bild
        </span>
        <div class="flex flex-wrap gap-2">
          <button
            type="button"
            phx-click="open"
            phx-target="#media-picker"
            phx-value-context="portrait"
            class="btn btn-outline btn-sm"
          >
            {if @portrait, do: "Bild ändern", else: "Bild wählen"}
          </button>
          <button
            :if={@portrait}
            type="button"
            phx-click="clear_portrait"
            class="btn btn-ghost btn-sm text-error"
          >
            Entfernen
          </button>
        </div>
      </div>
    </fieldset>
    """
  end
end
