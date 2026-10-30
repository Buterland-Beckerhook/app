defmodule BbhWeb.Admin.UserLive.Index do
  @moduledoc "Admin-only user management: invite, change role, Postfach queues, delete, login log."
  use BbhWeb, :live_view

  require Logger

  alias Bbh.Accounts
  alias Bbh.Accounts.AuthLog
  alias Bbh.Accounts.Passkeys
  alias Bbh.Accounts.User
  alias Bbh.Calendar.Event
  alias Bbh.Tickets.{Grants, Queue}
  alias BbhWeb.AdminList

  @roles [
    {"Redakteur", "editor"},
    {"Kalender", "calendar_editor"},
    {"Nur Postfach", "tickets"},
    {"Administrator", "admin"}
  ]

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign(page_title: "Benutzer", roles: @roles)
     |> assign(invite_form: to_form(%{"email" => "", "role" => "editor"}, as: "user"))
     |> assign(list_state: AdminList.init(sort: "email", dir: :asc))
     |> assign(reset_code: nil)
     # For the login log entry of a factor reset; connect info is only readable here.
     |> assign(
       client_ip: BbhWeb.ClientIp.from_socket(socket),
       user_agent: get_connect_info(socket, :user_agent)
     )
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
        with {:ok, user} <- id |> Accounts.get_user!() |> Accounts.update_user_role(role),
             do: remount_sessions(user)

        {:noreply, load_users(socket)}
    end
  end

  def handle_event("set_calendars", %{"user_id" => id} = params, socket) do
    calendars = params |> Map.get("calendars", []) |> Enum.reject(&(&1 == ""))
    id |> Accounts.get_user!() |> Accounts.update_user_calendars(calendars)
    {:noreply, load_users(socket)}
  end

  def handle_event("set_queues", %{"user_id" => id} = params, socket) do
    queues = Map.get(params, "queues", [])
    user = Accounts.get_user!(id)
    {:ok, _} = Grants.set_grants(socket.assigns.current_scope.user, user, queues)
    remount_sessions(user)
    {:noreply, load_users(socket)}
  end

  def handle_event("delete", %{"id" => id}, socket) do
    if id == socket.assigns.current_scope.user.id do
      {:noreply, put_flash(socket, :error, "Das eigene Konto kann nicht gelöscht werden.")}
    else
      user = Accounts.get_user!(id)
      # The tokens go with the user (FK cascade); fetch them first to drop the sockets.
      tokens = Accounts.list_user_session_tokens(user)
      {:ok, _} = Accounts.delete_user(user)
      BbhWeb.UserAuth.disconnect_sessions(tokens)
      {:noreply, socket |> put_flash(:info, "Benutzer gelöscht.") |> load_users()}
    end
  end

  def handle_event("logout_all", %{"id" => id}, socket) do
    user = Accounts.get_user!(id)
    user |> Accounts.delete_all_user_session_tokens() |> BbhWeb.UserAuth.disconnect_sessions()
    {:noreply, put_flash(socket, :info, "Benutzer von allen Geräten abgemeldet.")}
  end

  # Lost passkey/authenticator: wipe the factors and hand out a one-time code. The code
  # is shown here once and must reach the user out-of-band (in person, by phone) — the
  # mailbox alone must not be enough to enroll a new factor.
  def handle_event("reset_factors", %{"id" => id}, socket) do
    if id == socket.assigns.current_scope.user.id do
      {:noreply,
       put_flash(socket, :error, "Die eigene Anmeldung kann nicht zurückgesetzt werden.")}
    else
      user = Accounts.get_user!(id)
      {:ok, {code, sessions}} = Accounts.reset_second_factors(user)
      BbhWeb.UserAuth.disconnect_sessions(sessions)

      AuthLog.record(%{
        user: user,
        event: "factors_reset",
        ip: socket.assigns.client_ip,
        user_agent: socket.assigns.user_agent
      })

      Logger.info(
        "Second factors of #{user.email} reset by #{socket.assigns.current_scope.user.email}"
      )

      {:noreply, socket |> assign(reset_code: %{email: user.email, code: code}) |> load_users()}
    end
  end

  def handle_event("dismiss_reset_code", _params, socket),
    do: {:noreply, assign(socket, reset_code: nil)}

  def handle_event("list-" <> action, params, socket),
    do: {:noreply, AdminList.handle(action, params, socket, &load_users/1)}

  # Privileges are checked at on_mount only, so open tabs would keep the old ones.
  # Disconnecting makes the client reconnect and remount with the user re-read from the
  # DB; the sessions themselves stay valid.
  defp remount_sessions(user),
    do: user |> Accounts.list_user_session_tokens() |> BbhWeb.UserAuth.disconnect_sessions()

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

    assign(socket,
      users: meta.entries,
      list_meta: meta,
      passkey_user_ids: Passkeys.user_ids_with_passkeys(),
      queue_grants: Grants.grants_by_user()
    )
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
        <.button phx-disable-with="Sende…" class="btn btn-primary mb-2">
          Einladen
        </.button>
      </.form>

      <div :if={@reset_code} id="reset-code" role="alert" class="alert alert-warning mt-6 items-start">
        <.icon name="hero-key" class="size-6 shrink-0" />
        <div class="space-y-2">
          <p>
            Passkeys und 2FA von <strong>{@reset_code.email}</strong>
            wurden zurückgesetzt und alle Sitzungen beendet.
          </p>
          <p class="font-mono text-2xl tracking-widest">{@reset_code.code}</p>
          <p class="text-sm">
            Diesen Code bitte persönlich oder telefonisch weitergeben, nicht per E-Mail.
            Er ist {Bbh.Accounts.UserToken.factor_reset_validity_in_hours()} Stunden gültig
            und wird nur jetzt angezeigt. Nach der Anmeldung per Link fragt die Seite danach,
            erst dann lässt sich ein neuer Passkey oder 2FA einrichten.
          </p>
        </div>
        <button type="button" phx-click="dismiss_reset_code" class="btn btn-sm btn-ghost">
          Schließen
        </button>
      </div>

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
        <:col :let={u} label="Postfach">
          <form phx-change="set_queues" id={"queues-#{u.id}"} class="flex flex-wrap gap-x-3 gap-y-1">
            <input type="hidden" name="user_id" value={u.id} />
            <input type="hidden" name="queues[]" value="" />
            <label :for={{label, key} <- Queue.options()} class="flex items-center gap-1 text-sm">
              <input
                type="checkbox"
                name="queues[]"
                value={key}
                checked={key in Map.get(@queue_grants, u.id, [])}
                class="checkbox checkbox-xs"
              />
              {label}
            </label>
          </form>
        </:col>
        <:col :let={u} label="Passkey">
          {if MapSet.member?(@passkey_user_ids, u.id), do: "ja", else: "–"}
        </:col>
        <:col :let={u} label="2FA">{if User.totp_enabled?(u), do: "ja", else: "–"}</:col>
        <:col :let={u} label="Status">
          <.status_badge kind={:user} status={if u.confirmed_at, do: "confirmed", else: "pending"} />
        </:col>
        <:action :let={u}>
          <div class="flex items-center justify-end gap-2">
            <.link
              navigate={~p"/admin/benutzer/#{u.id}/anmeldungen"}
              class="link"
              title="Anmeldungen"
              aria-label="Anmeldungen"
            >
              <.icon name="hero-clock" class="size-5" />
            </.link>
            <.link
              :if={u.id != @current_scope.user.id}
              phx-click={JS.push("logout_all", value: %{id: u.id})}
              data-confirm="Diesen Benutzer von allen Geräten abmelden?"
              class="link"
              title="Von allen Geräten abmelden"
              aria-label="Von allen Geräten abmelden"
            >
              <.icon name="hero-arrow-left-start-on-rectangle" class="size-5" />
            </.link>
            <.link
              :if={u.id != @current_scope.user.id and u.confirmed_at}
              phx-click={JS.push("reset_factors", value: %{id: u.id})}
              data-confirm="Passkeys und 2FA dieses Benutzers zurücksetzen? Alle Sitzungen werden beendet; für die Neueinrichtung erhältst du einen Code, den du persönlich weitergibst."
              class="link"
              title="Passkeys und 2FA zurücksetzen"
              aria-label="Passkeys und 2FA zurücksetzen"
            >
              <.icon name="hero-key" class="size-5" />
            </.link>
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
          </div>
        </:action>
      </.table>

      <.list_pagination meta={@list_meta} />
    </Layouts.admin>
    """
  end
end
