defmodule BbhWeb.PushDeviceController do
  @moduledoc """
  Makes the browser in use one of the signed-in user's Postfach push devices. Like the
  Postfach itself this needs a strong session; the JSON pipeline answers 403 instead of
  a login redirect. A controller rather than a LiveView event for the User-Agent, which
  becomes the device description.
  """
  use BbhWeb, :controller

  alias Bbh.Accounts.User

  def create(conn, params) do
    scope = conn.assigns[:current_scope]

    if Bbh.Authz.can_access_tickets?(scope) and User.strong_auth?(scope.user) do
      user_agent = conn |> get_req_header("user-agent") |> List.first()

      case Bbh.Notifications.link_device(scope.user, params, user_agent: user_agent) do
        {:ok, _} -> json(conn, %{ok: true})
        {:error, _} -> conn |> put_status(:unprocessable_entity) |> json(%{ok: false})
      end
    else
      conn |> put_status(:forbidden) |> json(%{ok: false})
    end
  end
end
