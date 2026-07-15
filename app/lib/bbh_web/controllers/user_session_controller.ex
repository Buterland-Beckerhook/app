defmodule BbhWeb.UserSessionController do
  use BbhWeb, :controller

  alias Bbh.Accounts
  alias Bbh.Accounts.User
  alias BbhWeb.RateLimit
  alias BbhWeb.UserAuth

  def create(conn, %{"_action" => "confirmed"} = params) do
    create(conn, params, "User confirmed successfully.")
  end

  def create(conn, params) do
    create(conn, params, "Welcome back!")
  end

  # passkey login handoff: the assertion was already verified in the login
  # LiveView, which signs a short-lived token naming the authenticated user. A
  # passkey (with user-verification required) is inherently multi-factor, so we
  # skip the TOTP second-factor step here.
  defp create(conn, %{"user" => %{"passkey_token" => token} = user_params}, info) do
    case Phoenix.Token.verify(BbhWeb.Endpoint, "passkey_session", token, max_age: 60) do
      {:ok, user_id} ->
        user = Accounts.get_user!(user_id)
        conn |> put_flash(:info, info) |> UserAuth.log_in_user(user, user_params)

      _ ->
        conn
        |> put_flash(:error, "Anmeldung abgelaufen. Bitte erneut versuchen.")
        |> redirect(to: ~p"/users/log-in")
    end
  end

  # magic link login
  defp create(conn, %{"user" => %{"token" => token} = user_params}, info) do
    with :ok <- RateLimit.check("magic_login", RateLimit.client_ip(conn), 10, :timer.minutes(5)),
         {:ok, {user, tokens_to_disconnect}} <- Accounts.login_user_by_magic_link(token) do
      UserAuth.disconnect_sessions(tokens_to_disconnect)
      maybe_require_totp(conn, user, user_params, info)
    else
      {:error, retry_after} when is_integer(retry_after) ->
        conn
        |> put_flash(:error, "Zu viele Versuche. Bitte später erneut versuchen.")
        |> redirect(to: ~p"/users/log-in")

      _ ->
        conn
        |> put_flash(:error, "The link is invalid or it has expired.")
        |> redirect(to: ~p"/users/log-in")
    end
  end

  # No recognized credential in the params — e.g. a no-JS magic-link form POST that
  # only carries the email (LiveView normally intercepts it via phx-submit). Fail
  # closed with a friendly redirect instead of a FunctionClauseError / 500.
  defp create(conn, _params, _info) do
    conn
    |> put_flash(:error, "Anmeldung fehlgeschlagen. Bitte erneut versuchen.")
    |> redirect(to: ~p"/users/log-in")
  end

  def delete(conn, _params) do
    conn
    |> put_flash(:info, "Logged out successfully.")
    |> UserAuth.log_out_user()
  end

  # If the user has a TOTP second factor, hold the login and require a code first.
  defp maybe_require_totp(conn, %User{} = user, params, info) do
    if User.totp_enabled?(user) do
      conn
      |> put_session(:totp_pending_user_id, user.id)
      |> put_session(:totp_pending_remember, params["remember_me"] == "true")
      |> redirect(to: ~p"/users/totp")
    else
      conn
      |> put_flash(:info, info)
      |> UserAuth.maybe_put_enrollment_return_to(user)
      |> UserAuth.log_in_user(user, params)
    end
  end
end
