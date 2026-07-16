defmodule Bbh.Notifications do
  @moduledoc "Web Push subscriptions and sending (VAPID via web_push_elixir)."
  import Ecto.Query
  require Logger
  alias Bbh.Repo
  alias Bbh.Notifications.PushSubscription

  @categories ~w(termine news)

  # Upper bound on stored subscriptions — subscribe is public, so cap the table
  # to keep an attacker from flooding it. Updates to existing rows still work.
  @max_subscriptions 10_000

  # Only real push-service origins are accepted as endpoints. `notify/2` POSTs to
  # these URLs, so an unrestricted endpoint is an SSRF vector (internal metadata,
  # localhost, …). Match known hosts exactly plus per-provider subdomain suffixes.
  @allowed_push_hosts ~w(fcm.googleapis.com web.push.apple.com updates.push.services.mozilla.com)
  @allowed_push_host_suffixes ~w(.notify.windows.com .push.services.mozilla.com)

  @doc "The VAPID public key the browser needs to subscribe."
  def vapid_public_key, do: Application.get_env(:web_push_elixir, :vapid_public_key)

  @doc """
  Whether `endpoint` is an `https` URL pointing at a known push service.
  Used both when accepting a subscription and again before sending (SSRF guard).
  """
  def valid_push_endpoint?(endpoint) when is_binary(endpoint) do
    case URI.parse(endpoint) do
      %URI{scheme: "https", host: host} when is_binary(host) ->
        host in @allowed_push_hosts or
          Enum.any?(@allowed_push_host_suffixes, &String.ends_with?(host, &1))

      _ ->
        false
    end
  end

  def valid_push_endpoint?(_), do: false

  @doc "Create or update a subscription (keyed by endpoint)."
  def subscribe(%{"endpoint" => endpoint} = params) do
    existing = Repo.get_by(PushSubscription, endpoint: endpoint)

    with true <- valid_push_endpoint?(endpoint),
         :ok <- within_capacity(existing) do
      attrs = %{
        "endpoint" => endpoint,
        "keys_p256dh" => get_in(params, ["keys", "p256dh"]),
        "keys_auth" => get_in(params, ["keys", "auth"]),
        "categories" => normalize_categories(params["categories"])
      }

      (existing || %PushSubscription{})
      |> PushSubscription.changeset(attrs)
      |> Repo.insert_or_update()
    else
      false -> {:error, :invalid_endpoint}
      {:error, :capacity} -> {:error, :capacity}
    end
  end

  def subscribe(_params), do: {:error, :invalid_endpoint}

  defp within_capacity(nil) do
    if Repo.aggregate(PushSubscription, :count) < @max_subscriptions,
      do: :ok,
      else: {:error, :capacity}
  end

  defp within_capacity(_existing), do: :ok

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
    if valid_push_endpoint?(sub.endpoint) do
      do_send(sub, message)
    else
      # Reject/prune any stored endpoint that isn't a known push service (SSRF guard).
      Logger.warning("Dropping push subscription with untrusted endpoint: #{sub.endpoint}")
      Repo.delete(sub)
    end
  end

  defp do_send(sub, message) do
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
