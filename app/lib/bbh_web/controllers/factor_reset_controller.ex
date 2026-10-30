defmodule BbhWeb.FactorResetController do
  @moduledoc """
  Entry of the one-time code an admin hands over after resetting a user's second
  factors (`Bbh.Accounts.reset_second_factors/1`). A correct code marks the session so
  it may enroll a new passkey or TOTP; without it, a magic-link login (i.e. mailbox
  access) is not enough.
  """
  use BbhWeb, :controller

  alias Bbh.Accounts
  alias BbhWeb.RateLimit
  alias BbhWeb.UserAuth

  plug :require_pending_reset

  def new(conn, _params), do: render(conn, :new, error: nil)

  def create(conn, %{"reset" => %{"code" => code}}) do
    user = conn.assigns.current_scope.user

    # Keyed by user as well as IP: the code space is small enough that guessing must
    # not be spread across addresses.
    with :ok <- RateLimit.check("factor_reset_user", user.id, 5, :timer.minutes(15)),
         :ok <-
           RateLimit.check("factor_reset_ip", RateLimit.client_ip(conn), 10, :timer.minutes(15)),
         true <- Accounts.valid_factor_reset_code?(user, code) do
      conn
      |> UserAuth.put_factor_reset_verified(user)
      |> put_flash(:info, "Code bestätigt. Bitte richte jetzt einen Passkey oder 2FA ein.")
      |> redirect(to: ~p"/users/security")
    else
      {:error, _retry_after} ->
        render(conn, :new, error: "Zu viele Versuche. Bitte später erneut versuchen.")

      false ->
        conn
        |> UserAuth.log_auth_event(user, "factor_reset_failed")
        |> render(:new, error: "Ungültiger oder abgelaufener Code.")
    end
  end

  def create(conn, _params), do: render(conn, :new, error: "Bitte den Code eingeben.")

  defp require_pending_reset(conn, _opts) do
    if Accounts.factor_reset_pending?(conn.assigns.current_scope.user) do
      conn
    else
      conn |> redirect(to: ~p"/users/security") |> halt()
    end
  end
end
