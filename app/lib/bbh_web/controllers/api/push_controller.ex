defmodule BbhWeb.Api.PushController do
  @moduledoc "Web Push subscribe/unsubscribe endpoints (called by the service worker registration)."
  use BbhWeb, :controller

  def subscribe(conn, params) do
    case Bbh.Notifications.subscribe(params) do
      {:ok, _} -> json(conn, %{ok: true})
      {:error, _} -> conn |> put_status(:unprocessable_entity) |> json(%{ok: false})
    end
  end

  def unsubscribe(conn, %{"endpoint" => endpoint}) do
    Bbh.Notifications.unsubscribe(endpoint)
    json(conn, %{ok: true})
  end

  def unsubscribe(conn, _params), do: conn |> put_status(:bad_request) |> json(%{ok: false})
end
