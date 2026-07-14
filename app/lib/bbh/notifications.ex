defmodule Bbh.Notifications do
  @moduledoc "Web Push subscriptions and sending (VAPID via web_push_elixir)."
  import Ecto.Query
  require Logger
  alias Bbh.Repo
  alias Bbh.Notifications.PushSubscription

  @categories ~w(termine news)

  @doc "The VAPID public key the browser needs to subscribe."
  def vapid_public_key, do: Application.get_env(:web_push_elixir, :vapid_public_key)

  @doc "Create or update a subscription (keyed by endpoint)."
  def subscribe(%{"endpoint" => endpoint} = params) do
    attrs = %{
      "endpoint" => endpoint,
      "keys_p256dh" => get_in(params, ["keys", "p256dh"]),
      "keys_auth" => get_in(params, ["keys", "auth"]),
      "categories" => normalize_categories(params["categories"])
    }

    case Repo.get_by(PushSubscription, endpoint: endpoint) do
      nil -> %PushSubscription{}
      existing -> existing
    end
    |> PushSubscription.changeset(attrs)
    |> Repo.insert_or_update()
  end

  @doc "Remove a subscription by endpoint."
  def unsubscribe(endpoint) do
    Repo.delete_all(from s in PushSubscription, where: s.endpoint == ^endpoint)
    :ok
  end

  @doc """
  Send a notification to all subscribers of `category`. `payload` is a map with
  `title`, `body`, and `url`. Expired subscriptions are pruned. Runs the sends
  concurrently; safe to call from a Task.
  """
  def notify(category, %{} = payload) when category in @categories do
    message = Jason.encode!(payload)

    from(s in PushSubscription, where: fragment("? = ANY(?)", ^category, s.categories))
    |> Repo.all()
    |> Task.async_stream(&send_one(&1, message), max_concurrency: 10, on_timeout: :kill_task)
    |> Stream.run()
  end

  defp send_one(sub, message) do
    json =
      Jason.encode!(%{
        "endpoint" => sub.endpoint,
        "keys" => %{"p256dh" => sub.keys_p256dh, "auth" => sub.keys_auth}
      })

    case WebPushElixir.send_notification(json, message) do
      {:error, :expired} ->
        Repo.delete(sub)

      {:error, reason} ->
        Logger.warning("Web push failed for #{sub.endpoint}: #{inspect(reason)}")

      _ok ->
        sub |> Ecto.Changeset.change(last_used: DateTime.utc_now(:second)) |> Repo.update()
    end
  rescue
    e -> Logger.warning("Web push error for #{sub.endpoint}: #{inspect(e)}")
  end

  defp normalize_categories(cats) when is_list(cats), do: Enum.filter(cats, &(&1 in @categories))
  defp normalize_categories(_), do: @categories
end
