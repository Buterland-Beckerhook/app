defmodule BbhWeb.PushTesterController do
  @moduledoc """
  Lets an admin mark the push subscription of the browser they are using as a test
  receiver (or unmark it). Test receivers are the "Nur Testgeräte" target on
  /admin/push, for trying a message before it goes to every subscriber.
  """
  use BbhWeb, :controller

  alias Bbh.Accounts.User

  def update(conn, %{"endpoint" => endpoint, "tester" => tester}) when is_boolean(tester) do
    scope = conn.assigns[:current_scope]

    if User.admin?(scope && scope.user) do
      case Bbh.Notifications.set_tester(endpoint, tester) do
        {:ok, _} -> json(conn, %{ok: true, tester: tester})
        {:error, _} -> conn |> put_status(:not_found) |> json(%{ok: false})
      end
    else
      conn |> put_status(:forbidden) |> json(%{ok: false})
    end
  end

  def update(conn, _params), do: conn |> put_status(:bad_request) |> json(%{ok: false})
end
