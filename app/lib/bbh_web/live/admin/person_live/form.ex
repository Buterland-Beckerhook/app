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
    |> assign(page_title: "Neue Person", person: person)
    |> assign_form(Club.change_person(person))
  end

  defp apply_action(socket, :edit, %{"id" => id}) do
    person = Club.get_person!(id)

    socket
    |> assign(page_title: "Person bearbeiten", person: person)
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
      <.live_component module={BbhWeb.Admin.MediaPickerComponent} id="media-picker" />
    </Layouts.admin>
    """
  end
end
