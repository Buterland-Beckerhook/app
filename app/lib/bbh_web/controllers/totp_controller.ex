defmodule BbhWeb.TotpController do
  @moduledoc "Second-factor (TOTP) challenge that completes a pending login."
  use BbhWeb, :controller

  alias Bbh.Accounts
  alias BbhWeb.UserAuth

  plug :require_pending_user

  def new(conn, _params), do: render(conn, :new, error: nil)

  def create(conn, %{"totp" => %{"code" => code}}) do
    user = conn.assigns.pending_user

    if Accounts.valid_user_totp?(user, code) do
      remember = get_session(conn, :totp_pending_remember)

      conn
      |> delete_session(:totp_pending_user_id)
      |> delete_session(:totp_pending_remember)
      |> put_flash(:info, "Willkommen zurück!")
      |> UserAuth.log_in_user(user, %{"remember_me" => to_string(remember)})
    else
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
