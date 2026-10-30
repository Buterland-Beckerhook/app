defmodule BbhWeb.UserAuth do
  use BbhWeb, :verified_routes

  import Plug.Conn
  import Phoenix.Controller

  alias Bbh.Accounts
  alias Bbh.Accounts.Scope

  # Make the remember me cookie valid for 14 days. This should match
  # the session validity setting in UserToken.
  @max_cookie_age_in_days 14
  @remember_me_cookie "_bbh_web_user_remember_me"
  @remember_me_options [
    sign: true,
    max_age: @max_cookie_age_in_days * 24 * 60 * 60,
    same_site: "Lax"
  ]

  # How old the session token should be before a new one is issued. When a request is made
  # with a session token older than this value, then a new session token will be created
  # and the session and remember-me cookies (if set) will be updated with the new token.
  # Lowering this value will result in more tokens being created by active users. Increasing
  # it will result in less time before a session token expires for a user to get issued a new
  # token. This can be set to a value greater than `@max_cookie_age_in_days` to disable
  # the reissuing of tokens completely.
  @session_reissue_age_in_days 7

  @strong_auth_message "Für diesen Bereich ist eine Anmeldung mit Passkey oder " <>
                         "Zwei-Faktor-Code nötig."

  @doc """
  Logs the user in.

  `method` is how the user proved who they are (one of `Bbh.Accounts.User.auth_methods/0`);
  it is stored on the session token and decides `:require_strong_auth`.

  Redirects to the session's `:user_return_to` path
  or falls back to the `signed_in_path/1`.
  """
  def log_in_user(conn, user, params \\ %{}, method \\ nil) do
    user_return_to = get_session(conn, :user_return_to)

    conn
    # Consume it so it can't linger (the same-user renew path doesn't clear the
    # session), which would otherwise re-fire the same redirect on a later login.
    |> delete_session(:user_return_to)
    # A fresh login always mints a new token, also for a re-auth of the same user, so
    # the method of this login replaces the previous one.
    |> create_or_extend_session(%{user | auth_method: method}, params)
    |> log_auth_event(user, "login_succeeded", method)
    |> redirect(to: user_return_to || signed_in_path(conn))
  end

  @doc """
  Routes a magic-link login through the `/users/security` enrollment nudge when
  the user still lacks a passkey and/or a second factor.

  Call this *before* `log_in_user/3` on the magic-link paths only (never for
  passkey logins, which are already strongly authenticated). It leaves an
  existing `:user_return_to` untouched so a deep-link destination still wins.

  This guards the *automatic* nudge only. A user can still reach `/users/security`
  by navigating there explicitly (which stores it as a return path); that's fine —
  `SecuritySetup` redirects to the admin area when nothing is missing.
  """
  def maybe_put_enrollment_return_to(conn, user, method) do
    if get_session(conn, :user_return_to) == nil and needs_security_enrollment?(user, method) do
      put_session(conn, :user_return_to, ~p"/users/security")
    else
      conn
    end
  end

  # Only nudge towards what this session may actually set up: a session without a
  # second factor can enroll the *first* one, but once one exists, adding another needs
  # a strong session (see `on_mount(:require_enrolled_strong_auth, …)`).
  defp needs_security_enrollment?(user, method) do
    has_passkey = Accounts.Passkeys.has_passkey?(user)
    has_totp = Accounts.User.totp_enabled?(user)

    (not has_passkey or not has_totp) and
      (Accounts.User.strong_auth?(%{user | auth_method: method}) or
         not (has_passkey or has_totp))
  end

  @doc """
  Logs the user out.

  It clears all session data for safety. See renew_session.
  """
  def log_out_user(conn) do
    case conn.assigns[:current_scope] do
      %{user: %Accounts.User{} = user} ->
        log_auth_event(conn, user, "logged_out", user.auth_method)

      _ ->
        conn
    end

    user_token = get_session(conn, :user_token)
    user_token && Accounts.delete_user_session_token(user_token)

    if live_socket_id = get_session(conn, :live_socket_id) do
      BbhWeb.Endpoint.broadcast(live_socket_id, "disconnect", %{})
    end

    conn
    |> renew_session(nil)
    |> delete_resp_cookie(@remember_me_cookie, @remember_me_options)
    |> redirect(to: ~p"/")
  end

  @doc """
  Writes an entry to the login log (`Bbh.Accounts.AuthLog`) with the request's client
  IP and user agent. Returns the conn, so it fits a pipeline.
  """
  def log_auth_event(conn, user, event, method \\ nil) do
    Accounts.AuthLog.record(%{
      user: user,
      event: event,
      method: method,
      ip: BbhWeb.ClientIp.get(conn),
      user_agent: conn |> get_req_header("user-agent") |> List.first()
    })

    conn
  end

  @doc """
  Authenticates the user by looking into the session and remember me token.

  Will reissue the session token if it is older than the configured age.
  """
  def fetch_current_scope_for_user(conn, _opts) do
    with {token, conn} <- ensure_user_token(conn),
         {user, token_inserted_at} <- Accounts.get_user_by_session_token(token) do
      conn
      |> assign(:current_scope, Scope.for_user(user))
      |> maybe_reissue_user_session_token(user, token_inserted_at)
    else
      nil -> assign(conn, :current_scope, Scope.for_user(nil))
    end
  end

  defp ensure_user_token(conn) do
    if token = get_session(conn, :user_token) do
      {token, conn}
    else
      conn = fetch_cookies(conn, signed: [@remember_me_cookie])

      if token = conn.cookies[@remember_me_cookie] do
        {token, conn |> put_token_in_session(token) |> put_session(:user_remember_me, true)}
      else
        nil
      end
    end
  end

  # Reissue the session token if it is older than the configured reissue age.
  defp maybe_reissue_user_session_token(conn, user, token_inserted_at) do
    token_age = DateTime.diff(DateTime.utc_now(:second), token_inserted_at, :day)

    if token_age >= @session_reissue_age_in_days do
      create_or_extend_session(conn, user, %{})
    else
      conn
    end
  end

  # This function is the one responsible for creating session tokens
  # and storing them safely in the session and cookies. It may be called
  # either when logging in, during sudo mode, or to renew a session which
  # will soon expire.
  #
  # When the session is created, rather than extended, the renew_session
  # function will clear the session to avoid fixation attacks. See the
  # renew_session function to customize this behaviour.
  defp create_or_extend_session(conn, user, params) do
    token = Accounts.generate_user_session_token(user)
    remember_me = get_session(conn, :user_remember_me)

    conn
    |> renew_session(user)
    |> put_token_in_session(token)
    |> maybe_write_remember_me_cookie(token, params, remember_me)
  end

  # Do not renew session if the user is already logged in
  # to prevent CSRF errors or data being lost in tabs that are still open
  defp renew_session(conn, user) when conn.assigns.current_scope.user.id == user.id do
    conn
  end

  # This function renews the session ID and erases the whole
  # session to avoid fixation attacks. If there is any data
  # in the session you may want to preserve after log in/log out,
  # you must explicitly fetch the session data before clearing
  # and then immediately set it after clearing, for example:
  #
  #     defp renew_session(conn, _user) do
  #       delete_csrf_token()
  #       preferred_locale = get_session(conn, :preferred_locale)
  #
  #       conn
  #       |> configure_session(renew: true)
  #       |> clear_session()
  #       |> put_session(:preferred_locale, preferred_locale)
  #     end
  #
  defp renew_session(conn, _user) do
    delete_csrf_token()

    conn
    |> configure_session(renew: true)
    |> clear_session()
  end

  defp maybe_write_remember_me_cookie(conn, token, %{"remember_me" => "true"}, _),
    do: write_remember_me_cookie(conn, token)

  defp maybe_write_remember_me_cookie(conn, token, _params, true),
    do: write_remember_me_cookie(conn, token)

  defp maybe_write_remember_me_cookie(conn, _token, _params, _), do: conn

  defp write_remember_me_cookie(conn, token) do
    conn
    |> put_session(:user_remember_me, true)
    |> put_resp_cookie(@remember_me_cookie, token, @remember_me_options)
  end

  defp put_token_in_session(conn, token) do
    conn
    |> put_session(:user_token, token)
    |> put_session(:live_socket_id, user_session_topic(token))
  end

  @doc """
  Disconnects existing sockets for the given tokens.
  """
  def disconnect_sessions(tokens) do
    Enum.each(tokens, fn %{token: token} ->
      BbhWeb.Endpoint.broadcast(user_session_topic(token), "disconnect", %{})
    end)
  end

  defp user_session_topic(token), do: "users_sessions:#{Base.url_encode64(token)}"

  @doc """
  Handles mounting and authenticating the current_scope in LiveViews.

  ## `on_mount` arguments

    * `:mount_current_scope` - Assigns current_scope
      to socket assigns based on user_token, or nil if
      there's no user_token or no matching user.

    * `:require_authenticated` - Authenticates the user from the session,
      and assigns the current_scope to socket assigns based
      on user_token.
      Redirects to login page if there's no logged user.

  ## Examples

  Use the `on_mount` lifecycle macro in LiveViews to mount or authenticate
  the `current_scope`:

      defmodule BbhWeb.PageLive do
        use BbhWeb, :live_view

        on_mount {BbhWeb.UserAuth, :mount_current_scope}
        ...
      end

  Or use the `live_session` of your router to invoke the on_mount callback:

      live_session :authenticated, on_mount: [{BbhWeb.UserAuth, :require_authenticated}] do
        live "/profile", ProfileLive, :index
      end
  """
  def on_mount(:mount_current_scope, _params, session, socket) do
    {:cont, mount_current_scope(socket, session)}
  end

  def on_mount(:require_authenticated, _params, session, socket) do
    socket = mount_current_scope(socket, session)

    if socket.assigns.current_scope && socket.assigns.current_scope.user do
      {:cont, socket}
    else
      socket =
        socket
        |> Phoenix.LiveView.put_flash(
          :error,
          "Bitte melden Sie sich an, um diese Seite zu öffnen."
        )
        |> Phoenix.LiveView.redirect(to: ~p"/users/log-in")

      {:halt, socket}
    end
  end

  # Admin-only sections also need a strongly authenticated session.
  def on_mount(:require_admin, params, session, socket) do
    case on_mount(:require_strong_auth, params, session, socket) do
      {:cont, socket} ->
        if Accounts.User.admin?(socket.assigns.current_scope.user) do
          {:cont, socket}
        else
          socket =
            socket
            |> Phoenix.LiveView.put_flash(:error, "Nur für Administratoren.")
            |> Phoenix.LiveView.redirect(to: ~p"/admin")

          {:halt, socket}
        end

      halted ->
        halted
    end
  end

  # Any authenticated staff member (admin, editor, calendar_editor, tickets).
  def on_mount(:require_staff, params, session, socket),
    do: on_mount(:require_authenticated, params, session, socket)

  # Content sections: admins and content editors, but not calendar-only editors, and
  # only from a strongly authenticated session.
  def on_mount(:require_content_editor, params, session, socket) do
    case on_mount(:require_strong_auth, params, session, socket) do
      {:cont, socket} ->
        if BbhWeb.Authz.can_access_section?(socket.assigns.current_scope.user, :articles) do
          {:cont, socket}
        else
          socket =
            socket
            |> Phoenix.LiveView.put_flash(:error, "Kein Zugriff auf diesen Bereich.")
            |> Phoenix.LiveView.redirect(to: ~p"/admin/termine")

          {:halt, socket}
        end

      halted ->
        halted
    end
  end

  # Termine and Kalender teilen: every role but "Nur Postfach". The only section a plain
  # magic-link session may use; the public calendar inside it still needs a strong
  # session (`BbhWeb.Authz.can_manage_calendar?/2`).
  def on_mount(:require_events, params, session, socket) do
    case on_mount(:require_authenticated, params, session, socket) do
      {:cont, socket} ->
        if BbhWeb.Authz.can_access_section?(socket.assigns.current_scope.user, :events) do
          {:cont, socket}
        else
          socket =
            socket
            |> Phoenix.LiveView.put_flash(:error, "Kein Zugriff auf diesen Bereich.")
            |> Phoenix.LiveView.redirect(to: ~p"/admin")

          {:halt, socket}
        end

      halted ->
        halted
    end
  end

  # The Postfach: a queue grant (or admin) and a strongly authenticated session.
  def on_mount(:require_tickets, params, session, socket) do
    case on_mount(:require_strong_auth, params, session, socket) do
      {:cont, socket} ->
        if BbhWeb.Authz.can_access_tickets?(socket.assigns.current_scope) do
          {:cont, socket}
        else
          socket =
            socket
            |> Phoenix.LiveView.put_flash(:error, "Kein Zugriff auf das Postfach.")
            |> Phoenix.LiveView.redirect(to: ~p"/admin")

          {:halt, socket}
        end

      halted ->
        halted
    end
  end

  # Sensitive areas (everything but Termine and the dashboard): the session must have
  # been established with a passkey or a magic link plus TOTP code — see
  # `Bbh.Accounts.User.strong_auth?/1`.
  def on_mount(:require_strong_auth, params, session, socket) do
    case on_mount(:require_authenticated, params, session, socket) do
      {:cont, socket} ->
        user = socket.assigns.current_scope.user

        if Accounts.User.strong_auth?(user) do
          {:cont, socket}
        else
          socket =
            socket
            |> Phoenix.LiveView.put_flash(:error, @strong_auth_message)
            |> Phoenix.LiveView.redirect(to: strong_auth_path(user))

          {:halt, socket}
        end

      halted ->
        halted
    end
  end

  # Account security (settings, the enrollment nudge): once the user has a second
  # factor, changing sign-in methods, the email or API tokens needs a session that used
  # it — otherwise mailbox access alone would let an attacker enroll their own passkey
  # or TOTP and so reach the strong-auth areas. Without any factor yet, a plain session
  # may enter to set up the first one.
  def on_mount(:require_enrolled_strong_auth, params, session, socket) do
    case on_mount(:require_authenticated, params, session, socket) do
      {:cont, socket} ->
        if second_factor?(socket.assigns.current_scope.user),
          do: on_mount(:require_strong_auth, params, session, socket),
          else: {:cont, socket}

      halted ->
        halted
    end
  end

  def on_mount(:require_sudo_mode, _params, session, socket) do
    socket = mount_current_scope(socket, session)

    if Accounts.sudo_mode?(socket.assigns.current_scope.user, -10) do
      {:cont, socket}
    else
      socket =
        socket
        |> Phoenix.LiveView.put_flash(
          :error,
          "Bitte melden Sie sich erneut an, um diese Seite zu öffnen."
        )
        |> Phoenix.LiveView.redirect(to: ~p"/users/log-in")

      {:halt, socket}
    end
  end

  defp mount_current_scope(socket, session) do
    Phoenix.Component.assign_new(socket, :current_scope, fn ->
      {user, _} =
        if user_token = session["user_token"] do
          Accounts.get_user_by_session_token(user_token)
        end || {nil, nil}

      Scope.for_user(user)
    end)
  end

  @doc "Returns the path to redirect to after log in. All accounts are staff → admin area."
  def signed_in_path(_conn), do: ~p"/admin"

  @doc """
  Plug for routes that require the user to be authenticated.
  """
  def require_authenticated_user(conn, _opts) do
    if conn.assigns.current_scope && conn.assigns.current_scope.user do
      conn
    else
      conn
      |> put_flash(:error, "Bitte melden Sie sich an, um diese Seite zu öffnen.")
      |> maybe_store_return_to()
      |> redirect(to: ~p"/users/log-in")
      |> halt()
    end
  end

  @doc """
  Plug counterpart of `on_mount(:require_strong_auth, …)` for controllers (attachment
  and PDF downloads). Must run after `require_authenticated_user/2`.
  """
  def require_strong_auth(conn, _opts) do
    user = conn.assigns.current_scope.user

    if Accounts.User.strong_auth?(user) do
      conn
    else
      conn
      |> put_flash(:error, @strong_auth_message)
      |> maybe_store_return_to()
      |> redirect(to: strong_auth_path(user))
      |> halt()
    end
  end

  # Someone who has a second factor only needs to log in again with it; someone without
  # one has to set it up first.
  defp strong_auth_path(user) do
    if second_factor?(user), do: ~p"/users/log-in", else: ~p"/users/security"
  end

  defp second_factor?(user),
    do: Accounts.Passkeys.has_passkey?(user) or Accounts.User.totp_enabled?(user)

  defp maybe_store_return_to(%{method: "GET"} = conn) do
    put_session(conn, :user_return_to, current_path(conn))
  end

  defp maybe_store_return_to(conn), do: conn
end
