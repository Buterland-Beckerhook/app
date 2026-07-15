defmodule BbhWeb.Admin.UserLive.Index do
  @moduledoc "Admin-only user management: invite, change role, delete."
  use BbhWeb, :live_view

  alias Bbh.Accounts
  alias Bbh.Accounts.User
  alias Bbh.Calendar.Event
  alias BbhWeb.AdminList

  @roles [
    {"Redakteur", "editor"},
    {"Kalender", "calendar_editor"},
    {"Administrator", "admin"}
  ]

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign(page_title: "Benutzer", roles: @roles)
     |> assign(invite_form: to_form(%{"email" => "", "role" => "editor"}, as: "user"))
     |> assign(list_state: AdminList.init(sort: "email", dir: :asc))
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

  def handle_event("set_calendars", %{"user_id" => id} = params, socket) do
    calendars = params |> Map.get("calendars", []) |> Enum.reject(&(&1 == ""))
    id |> Accounts.get_user!() |> Accounts.update_user_calendars(calendars)
    {:noreply, load_users(socket)}
  end

  def handle_event("delete", %{"id" => id}, socket) do
    if id == socket.assigns.current_scope.user.id do
      {:noreply, put_flash(socket, :error, "Das eigene Konto kann nicht gelöscht werden.")}
    else
      id |> Accounts.get_user!() |> Accounts.delete_user()
      {:noreply, socket |> put_flash(:info, "Benutzer gelöscht.") |> load_users()}
    end
  end

  def handle_event("list-" <> action, params, socket),
    do: {:noreply, AdminList.handle(action, params, socket, &load_users/1)}

  # An admin being changed to a non-admin role while they are the only admin left.
  defp demoting_last_admin?(id, role) do
    user = Accounts.get_user!(id)
    user.role == "admin" and role != "admin" and Accounts.count_admins() <= 1
  end

  defp load_users(socket) do
    meta =
      AdminList.process(Accounts.list_users(), socket.assigns.list_state,
        search: [& &1.email],
        sort: %{"email" => & &1.email, "role" => & &1.role}
      )

    assign(socket, users: meta.entries, list_meta: meta)
  end

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

      <.list_search q={@list_meta.q} placeholder="Nach E-Mail suchen…" />

      <.table id="users" rows={@users} sort={@list_meta.sort} dir={@list_meta.dir}>
        <:col :let={u} label="E-Mail" sort_key="email">
          <span class="font-medium">{u.email}</span>
        </:col>
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
        <:col :let={u} label="Kalender">
          <form
            :if={u.role in ["editor", "calendar_editor"]}
            phx-change="set_calendars"
            id={"cals-#{u.id}"}
            class="flex flex-wrap gap-x-3 gap-y-1"
          >
            <input type="hidden" name="user_id" value={u.id} />
            <input type="hidden" name="calendars[]" value="" />
            <label :for={cal <- Event.calendars()} class="flex items-center gap-1 text-sm">
              <input
                type="checkbox"
                name="calendars[]"
                value={cal}
                checked={cal in u.calendars}
                class="checkbox checkbox-xs"
              />
              {Event.calendar_label(cal)}
            </label>
          </form>
          <span :if={u.role not in ["editor", "calendar_editor"]} class="text-base-content/40">
            –
          </span>
        </:col>
        <:col :let={u} label="2FA">{if User.totp_enabled?(u), do: "ja", else: "–"}</:col>
        <:col :let={u} label="Status">
          <.status_badge kind={:user} status={if u.confirmed_at, do: "confirmed", else: "pending"} />
        </:col>
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

      <.list_pagination meta={@list_meta} />
    </Layouts.admin>
    """
  end
end
