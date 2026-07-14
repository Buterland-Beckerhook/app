defmodule BbhWeb.Admin.UserLive.Index do
  @moduledoc "Admin-only user management: invite, change role, delete."
  use BbhWeb, :live_view

  alias Bbh.Accounts
  alias Bbh.Accounts.User

  @roles [{"Redakteur", "editor"}, {"Administrator", "admin"}]

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign(page_title: "Benutzer", roles: @roles)
     |> assign(invite_form: to_form(%{"email" => "", "role" => "editor"}, as: "user"))
     |> load_users()}
  end

  @impl true
  def handle_event("invite", %{"user" => %{"email" => email, "role" => role}}, socket) do
    case Accounts.invite_user(%{"email" => email, "role" => role}, &url(~p"/users/log-in/#{&1}")) do
      {:ok, user} ->
        {:noreply,
         socket
         |> put_flash(:info, "Einladung an #{user.email} gesendet.")
         |> assign(invite_form: to_form(%{"email" => "", "role" => "editor"}, as: "user"))
         |> load_users()}

      {:error, _changeset} ->
        {:noreply,
         put_flash(
           socket,
           :error,
           "Einladung fehlgeschlagen (E-Mail ungültig oder bereits vergeben)."
         )}
    end
  end

  def handle_event("set_role", %{"user_id" => id, "role" => role}, socket) do
    cond do
      id == socket.assigns.current_scope.user.id ->
        {:noreply,
         socket
         |> put_flash(:error, "Die eigene Rolle kann nicht geändert werden.")
         |> load_users()}

      demoting_last_admin?(id, role) ->
        {:noreply,
         socket
         |> put_flash(:error, "Der letzte Administrator kann nicht herabgestuft werden.")
         |> load_users()}

      true ->
        id |> Accounts.get_user!() |> Accounts.update_user_role(role)
        {:noreply, load_users(socket)}
    end
  end

  def handle_event("delete", %{"id" => id}, socket) do
    if id == socket.assigns.current_scope.user.id do
      {:noreply, put_flash(socket, :error, "Das eigene Konto kann nicht gelöscht werden.")}
    else
      id |> Accounts.get_user!() |> Accounts.delete_user()
      {:noreply, socket |> put_flash(:info, "Benutzer gelöscht.") |> load_users()}
    end
  end

  # An admin being changed to a non-admin role while they are the only admin left.
  defp demoting_last_admin?(id, role) do
    user = Accounts.get_user!(id)
    user.role == "admin" and role != "admin" and Accounts.count_admins() <= 1
  end

  defp load_users(socket), do: assign(socket, :users, Accounts.list_users())

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.admin flash={@flash} current_scope={@current_scope} active={:users}>
      <.header>
        Benutzer
        <:subtitle>Zugänge einladen und verwalten (nur Administratoren).</:subtitle>
      </.header>

      <.form
        for={@invite_form}
        id="invite-form"
        phx-submit="invite"
        class="mt-6 flex flex-wrap items-end gap-2"
      >
        <.input field={@invite_form[:email]} type="email" label="E-Mail einladen" required />
        <.input field={@invite_form[:role]} type="select" label="Rolle" options={@roles} />
        <.button variant="primary" phx-disable-with="Sende…">Einladen</.button>
      </.form>

      <.table id="users" rows={@users}>
        <:col :let={u} label="E-Mail"><span class="font-medium">{u.email}</span></:col>
        <:col :let={u} label="Rolle">
          <form phx-change="set_role" id={"role-#{u.id}"}>
            <input type="hidden" name="user_id" value={u.id} />
            <select name="role" class="select select-bordered select-sm">
              <option :for={{label, value} <- @roles} value={value} selected={u.role == value}>
                {label}
              </option>
            </select>
          </form>
        </:col>
        <:col :let={u} label="2FA">{if User.totp_enabled?(u), do: "ja", else: "–"}</:col>
        <:col :let={u} label="Status">{if u.confirmed_at, do: "Bestätigt", else: "Ausstehend"}</:col>
        <:action :let={u}>
          <.link
            :if={u.id != @current_scope.user.id}
            phx-click={JS.push("delete", value: %{id: u.id})}
            data-confirm="Diesen Benutzer wirklich löschen?"
            class="link link-error"
            title="Löschen"
            aria-label="Löschen"
          >
            <.icon name="hero-trash" class="size-5" />
          </.link>
        </:action>
      </.table>
    </Layouts.admin>
    """
  end
end
