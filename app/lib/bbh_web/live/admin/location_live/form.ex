defmodule BbhWeb.Admin.LocationLive.Form do
  use BbhWeb, :live_view

  alias Bbh.Calendar
  alias Bbh.Calendar.Location

  @impl true
  def mount(params, _session, socket) do
    {:ok, apply_action(socket, socket.assigns.live_action, params)}
  end

  defp apply_action(socket, :new, _params) do
    socket
    |> assign(page_title: "Neuer Ort", location: %Location{})
    |> assign_form(Calendar.change_location(%Location{}))
  end

  defp apply_action(socket, :edit, %{"id" => id}) do
    location = Calendar.get_location!(id)

    socket
    |> assign(page_title: "Ort bearbeiten", location: location)
    |> assign_form(Calendar.change_location(location))
  end

  @impl true
  def handle_event("validate", %{"location" => params}, socket) do
    changeset =
      socket.assigns.location |> Calendar.change_location(params) |> Map.put(:action, :validate)

    {:noreply, assign_form(socket, changeset)}
  end

  def handle_event("save", %{"location" => params}, socket) do
    save(socket, socket.assigns.live_action, params)
  end

  defp save(socket, :new, params) do
    case Calendar.create_location(params) do
      {:ok, _} ->
        {:noreply,
         socket |> put_flash(:info, "Ort erstellt.") |> push_navigate(to: ~p"/admin/orte")}

      {:error, changeset} ->
        {:noreply, assign_form(socket, changeset)}
    end
  end

  defp save(socket, :edit, params) do
    case Calendar.update_location(socket.assigns.location, params) do
      {:ok, _} ->
        {:noreply,
         socket |> put_flash(:info, "Ort gespeichert.") |> push_navigate(to: ~p"/admin/orte")}

      {:error, changeset} ->
        {:noreply, assign_form(socket, changeset)}
    end
  end

  defp assign_form(socket, changeset),
    do: assign(socket, :form, to_form(changeset, as: "location"))

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.admin flash={@flash} current_scope={@current_scope} active={:locations}>
      <.header>{@page_title}</.header>

      <.form
        for={@form}
        id="location-form"
        phx-change="validate"
        phx-submit="save"
        class="mt-6 space-y-4"
      >
        <.input field={@form[:key]} label="Schlüssel" required />
        <.input field={@form[:name]} label="Name" required />
        <.input field={@form[:street]} label="Straße" />
        <div class="grid grid-cols-2 gap-4">
          <.input field={@form[:zip]} label="PLZ" />
          <.input field={@form[:city]} label="Ort" />
        </div>
        <div class="grid grid-cols-2 gap-4">
          <.input field={@form[:lat]} type="number" step="any" label="Breitengrad" />
          <.input field={@form[:lng]} type="number" step="any" label="Längengrad" />
        </div>
        <.input field={@form[:maps_url]} label="Karten-URL" />
        <.input field={@form[:url]} label="Website" />

        <div class="flex gap-2">
          <.button variant="primary" phx-disable-with="Speichern…">Speichern</.button>
          <.button navigate={~p"/admin/orte"}>Abbrechen</.button>
        </div>
      </.form>
    </Layouts.admin>
    """
  end
end
