defmodule BbhWeb.Api.PushController do
  @moduledoc "Web Push subscribe/unsubscribe endpoints (called by the service worker registration)."
  use BbhWeb, :controller

  alias BbhWeb.RateLimit

  def subscribe(conn, params) do
    case RateLimit.check("push_subscribe", RateLimit.client_ip(conn), 20, :timer.minutes(1)) do
      :ok ->
        user_agent = conn |> get_req_header("user-agent") |> List.first()

        case Bbh.Notifications.subscribe(params, user_agent: user_agent) do
          {:ok, _} -> json(conn, %{ok: true})
          {:error, _} -> conn |> put_status(:unprocessable_entity) |> json(%{ok: false})
        end

      {:error, _retry_after} ->
        conn |> put_status(:too_many_requests) |> json(%{ok: false})
    end
  end

  @doc """
  The server-side state of a browser's subscription, so the page can show whether
  notifications are on (and for which categories) after a reload.
  """
  def status(conn, %{"endpoint" => endpoint}) do
    case RateLimit.check("push_status", RateLimit.client_ip(conn), 60, :timer.minutes(1)) do
      :ok ->
        case Bbh.Notifications.subscription_status(endpoint) do
          {:ok, %{categories: categories, tester: tester, label: label}} ->
            json(conn, %{subscribed: true, categories: categories, tester: tester, label: label})

          :error ->
            json(conn, %{subscribed: false})
        end

      {:error, _retry_after} ->
        conn |> put_status(:too_many_requests) |> json(%{ok: false})
    end
  end

  def status(conn, _params), do: conn |> put_status(:bad_request) |> json(%{ok: false})

  def unsubscribe(conn, %{"endpoint" => endpoint}) do
    Bbh.Notifications.unsubscribe(endpoint)
    json(conn, %{ok: true})
  end

  def unsubscribe(conn, _params), do: conn |> put_status(:bad_request) |> json(%{ok: false})
end
