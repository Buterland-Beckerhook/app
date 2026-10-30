defmodule BbhWeb.Admin.TrophyLive.TrophyForm do
  use BbhWeb, :live_view

  alias Bbh.Club
  alias Bbh.Club.Trophy

  @impl true
  def mount(params, _session, socket) do
    {:ok, apply_action(socket, socket.assigns.live_action, params)}
  end

  defp apply_action(socket, :new, _params) do
    socket
    |> assign(page_title: "Neuer Pokal", trophy: %Trophy{})
    |> assign_form(Club.change_trophy(%Trophy{}))
  end

  defp apply_action(socket, :edit, %{"id" => id}) do
    trophy = Club.get_trophy!(id)

    socket
    |> assign(page_title: "Pokal bearbeiten", trophy: trophy)
    |> assign_form(Club.change_trophy(trophy))
  end

  @impl true
  def handle_event("validate", %{"trophy" => params}, socket) do
    changeset =
      socket.assigns.trophy |> Club.change_trophy(params) |> Map.put(:action, :validate)

    {:noreply, assign_form(socket, changeset)}
  end

  def handle_event("save", %{"trophy" => params}, socket) do
    result =
      case socket.assigns.live_action do
        :new -> Club.create_trophy(params)
        :edit -> Club.update_trophy(socket.assigns.trophy, params)
      end

    case result do
      {:ok, _} ->
        {:noreply,
         socket |> put_flash(:info, "Pokal gespeichert.") |> push_navigate(to: ~p"/admin/pokale")}

      {:error, changeset} ->
        {:noreply, assign_form(socket, changeset)}
    end
  end

  def handle_event("delete", %{"confirm" => confirm}, socket) do
    trophy = socket.assigns.trophy

    cond do
      not Bbh.Authz.can_delete?(socket.assigns.current_scope.user, trophy) ->
        {:noreply, put_flash(socket, :error, "Keine Berechtigung zum Löschen.")}

      confirm != trophy.name ->
        {:noreply, put_flash(socket, :error, "Der eingegebene Wert stimmt nicht überein.")}

      true ->
        case Club.delete_trophy(trophy) do
          {:ok, _} ->
            {:noreply,
             socket |> put_flash(:info, "Pokal gelöscht.") |> push_navigate(to: ~p"/admin/pokale")}

          {:error, :has_wins} ->
            {:noreply,
             put_flash(socket, :error, "Der Pokal hat Sieger – erst die Sieger löschen.")}
        end
    end
  end

  defp assign_form(socket, changeset), do: assign(socket, :form, to_form(changeset, as: "trophy"))

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.admin flash={@flash} current_scope={@current_scope} active={:trophies}>
      <.header>{@page_title}</.header>

      <.form
        for={@form}
        id="trophy-form"
        phx-change="validate"
        phx-submit="save"
        class="mt-6 space-y-4"
      >
        <.input field={@form[:name]} label="Name" required />
        <div class="grid grid-cols-2 gap-4">
          <.input field={@form[:since]} type="number" label="Seit (Jahr)" />
          <.input field={@form[:sort_order]} type="number" label="Reihenfolge (Spalte)" />
        </div>
        <.input
          field={@form[:description]}
          type="textarea"
          label="Beschreibung"
          placeholder="Wer darf schießen, wer hat den Pokal gestiftet …"
        />

        <div class="flex gap-2">
          <.button variant="primary" phx-disable-with="Speichern…">Speichern</.button>
          <.button navigate={~p"/admin/pokale"}>Abbrechen</.button>
        </div>
      </.form>

      <.danger_zone
        :if={@live_action == :edit and Bbh.Authz.can_delete?(@current_scope.user, @trophy)}
        confirm_value={@trophy.name}
      >
        Der Pokal „{@trophy.name}“ wird dauerhaft gelöscht – nur möglich, solange er keine
        Sieger hat.
      </.danger_zone>
    </Layouts.admin>
    """
  end
end
