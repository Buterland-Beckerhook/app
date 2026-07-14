defmodule BbhWeb.TotpController do
  @moduledoc "Second-factor (TOTP) challenge that completes a pending login."
  use BbhWeb, :controller

  alias Bbh.Accounts
  alias BbhWeb.RateLimit
  alias BbhWeb.UserAuth

  plug :require_pending_user

  def new(conn, _params), do: render(conn, :new, error: nil)

  def create(conn, %{"totp" => %{"code" => code}}) do
    user = conn.assigns.pending_user

    with :ok <- RateLimit.check("totp", RateLimit.client_ip(conn), 10, :timer.minutes(5)),
         true <- Accounts.valid_user_totp?(user, code) do
      remember = get_session(conn, :totp_pending_remember)

      conn
      |> delete_session(:totp_pending_user_id)
      |> delete_session(:totp_pending_remember)
      |> put_flash(:info, "Willkommen zurück!")
      |> UserAuth.log_in_user(user, %{"remember_me" => to_string(remember)})
    else
      {:error, _retry_after} ->
        render(conn, :new, error: "Zu viele Versuche. Bitte später erneut versuchen.")

      false ->
        render(conn, :new, error: "Ungültiger Code. Bitte erneut versuchen.")
    end
  end

  defp require_pending_user(conn, _opts) do
    case get_session(conn, :totp_pending_user_id) do
      nil ->
        conn |> redirect(to: ~p"/users/log-in") |> halt()

      id ->
        assign(conn, :pending_user, Accounts.get_user!(id))
    end
  end
end
