defmodule BbhWeb.Admin.TrophyLive.WinForm do
  use BbhWeb, :live_view

  alias Bbh.Club
  alias Bbh.Club.TrophyWin

  @impl true
  def mount(params, _session, socket) do
    {:ok,
     socket
     |> assign(:trophy_options, Club.trophy_options())
     |> apply_action(socket.assigns.live_action, params)}
  end

  # A new winner is nearly always for the current year — the Pokalschießen in January,
  # the Biwak in May.
  defp apply_action(socket, :new, params) do
    win = %TrophyWin{year: Bbh.Time.now().year, trophy_id: params["pokal"]}

    socket
    |> assign(page_title: "Neuer Sieger", win: win)
    |> assign_form(Club.change_trophy_win(win))
  end

  defp apply_action(socket, :edit, %{"id" => id}) do
    win = Club.get_trophy_win!(id)

    socket
    |> assign(page_title: "Sieger bearbeiten", win: win)
    |> assign_form(Club.change_trophy_win(win))
  end

  @impl true
  def handle_event("validate", %{"trophy_win" => params}, socket) do
    changeset =
      socket.assigns.win |> Club.change_trophy_win(params) |> Map.put(:action, :validate)

    {:noreply, assign_form(socket, changeset)}
  end

  def handle_event("save", %{"trophy_win" => params}, socket) do
    result =
      case socket.assigns.live_action do
        :new -> Club.create_trophy_win(params)
        :edit -> Club.update_trophy_win(socket.assigns.win, params)
      end

    case result do
      {:ok, _} ->
        {:noreply,
         socket |> put_flash(:info, "Sieger gespeichert.") |> push_navigate(to: ~p"/admin/pokale")}

      {:error, changeset} ->
        {:noreply, assign_form(socket, changeset)}
    end
  end

  def handle_event("delete", %{"confirm" => confirm}, socket) do
    win = socket.assigns.win

    cond do
      not Bbh.Authz.can_delete?(socket.assigns.current_scope.user, win) ->
        {:noreply, put_flash(socket, :error, "Keine Berechtigung zum Löschen.")}

      confirm == win.winner ->
        {:ok, _} = Club.delete_trophy_win(socket.assigns.current_scope, win)

        {:noreply,
         socket |> put_flash(:info, "Sieger gelöscht.") |> push_navigate(to: ~p"/admin/pokale")}

      true ->
        {:noreply, put_flash(socket, :error, "Der eingegebene Wert stimmt nicht überein.")}
    end
  end

  defp assign_form(socket, changeset),
    do: assign(socket, :form, to_form(changeset, as: "trophy_win"))

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.admin flash={@flash} current_scope={@current_scope} active={:trophies}>
      <.header>{@page_title}</.header>

      <.form
        for={@form}
        id="trophy-win-form"
        phx-change="validate"
        phx-submit="save"
        class="mt-6 space-y-4"
      >
        <.input
          field={@form[:trophy_id]}
          type="select"
          label="Pokal"
          prompt="Pokal wählen …"
          options={@trophy_options}
          required
        />
        <div class="grid grid-cols-2 gap-4">
          <.input field={@form[:year]} type="number" label="Jahr" required />
          <.input field={@form[:rings]} type="number" label="Ringe" />
        </div>
        <.input field={@form[:winner]} label="Sieger" required />
        <.input
          field={@form[:note]}
          label="Notiz"
          placeholder="optional, erscheint klein unter dem Namen"
        />

        <div class="flex gap-2">
          <.button variant="primary" phx-disable-with="Speichern…">Speichern</.button>
          <.button navigate={~p"/admin/pokale"}>Abbrechen</.button>
        </div>
      </.form>

      <.danger_zone
        :if={@live_action == :edit and Bbh.Authz.can_delete?(@current_scope.user, @win)}
        confirm_value={@win.winner}
      >
        Der Eintrag „{@win.winner}, {@win.year}“ wird dauerhaft gelöscht.
      </.danger_zone>
    </Layouts.admin>
    """
  end
end
