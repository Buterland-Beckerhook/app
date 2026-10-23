defmodule BbhWeb.PushLabelController do
  @moduledoc """
  Lets an admin name the push subscription of the browser they are using ("Roberts
  iPhone"), so their own devices can be told apart in /admin/push. Like the tester
  flag, the device proves itself with its endpoint — a name can only be set from the
  device it names.
  """
  use BbhWeb, :controller

  alias Bbh.Accounts.User

  def update(conn, %{"endpoint" => endpoint, "label" => label})
      when is_binary(endpoint) and is_binary(label) do
    scope = conn.assigns[:current_scope]

    if User.admin?(scope && scope.user) do
      case Bbh.Notifications.set_label(endpoint, label) do
        {:ok, sub} -> json(conn, %{ok: true, label: sub.label})
        {:error, :too_long} -> conn |> put_status(:unprocessable_entity) |> json(%{ok: false})
        {:error, _} -> conn |> put_status(:not_found) |> json(%{ok: false})
      end
    else
      conn |> put_status(:forbidden) |> json(%{ok: false})
    end
  end

  def update(conn, _params), do: conn |> put_status(:bad_request) |> json(%{ok: false})
end
