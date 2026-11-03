defmodule Bbh.Notifications do
  @moduledoc "Web Push subscriptions and sending (VAPID via web_push_elixir)."
  import Ecto.Query
  require Logger
  alias Bbh.Accounts.User
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
  Run a notification side effect off the request via `Bbh.TaskSupervisor`.

  Set `config :bbh, Bbh.Notifications, async: false` (tests) to run it inline
  instead — a detached task would otherwise borrow and outlive the Ecto SQL
  sandbox connection, poisoning the pool for later async tests.
  """
  def dispatch(fun) when is_function(fun, 0) do
    if Application.get_env(:bbh, __MODULE__, [])[:async] == false do
      fun.()
    else
      Task.Supervisor.start_child(Bbh.TaskSupervisor, fun)
    end

    :ok
  end

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

  @doc """
  Create or update a subscription (keyed by endpoint). `opts[:user_agent]` — the
  subscribing browser's User-Agent — is reduced to a short device description
  (`Bbh.Notifications.Device`); the raw header is not stored.
  """
  def subscribe(params, opts \\ [])

  def subscribe(%{"endpoint" => endpoint} = params, opts) do
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
      |> put_device(opts[:user_agent])
      |> Repo.insert_or_update()
    else
      false -> {:error, :invalid_endpoint}
      {:error, :capacity} -> {:error, :capacity}
    end
  end

  def subscribe(_params, _opts), do: {:error, :invalid_endpoint}

  # A re-subscribe without a User-Agent keeps the description already stored.
  defp put_device(changeset, user_agent) do
    case Bbh.Notifications.Device.describe(user_agent) do
      nil -> changeset
      device -> Ecto.Changeset.put_change(changeset, :device, device)
    end
  end

  defp within_capacity(nil) do
    if Repo.aggregate(PushSubscription, :count) < @max_subscriptions,
      do: :ok,
      else: {:error, :capacity}
  end

  defp within_capacity(_existing), do: :ok

  @doc """
  What the server knows about the subscription for `endpoint`: `{:ok, %{categories:,
  tester:, label:, postfach:}}` or `:error` when there is none. Lets a browser show its
  real state after a reload — the endpoint is a secret capability URL, so knowing it is the proof.
  """
  def subscription_status(endpoint) when is_binary(endpoint) do
    case Repo.get_by(PushSubscription, endpoint: endpoint) do
      nil -> :error
      sub ->
        {:ok,
         %{
           categories: sub.categories,
           tester: sub.tester,
           label: sub.label,
           postfach: not is_nil(sub.user_id)
         }}
    end
  end

  def subscription_status(_), do: :error

  @doc """
  Flag (or unflag) the subscription for `endpoint` as a test receiver. Callers must
  have checked that the current user is an admin.
  """
  def set_tester(endpoint, tester?) when is_binary(endpoint) and is_boolean(tester?) do
    case Repo.get_by(PushSubscription, endpoint: endpoint) do
      nil -> {:error, :not_found}
      sub -> sub |> Ecto.Changeset.change(tester: tester?) |> Repo.update()
    end
  end

  def set_tester(_endpoint, _tester?), do: {:error, :not_found}

  @doc """
  Name the subscription for `endpoint` (blank clears the name). The endpoint is the
  proof of possession: only the device itself knows it, so a name always lands on the
  device it was typed on. Callers must have checked that the current user is an admin.
  Returns `{:error, :too_long}` beyond `PushSubscription.label_max/0` characters.
  """
  def set_label(endpoint, label) when is_binary(endpoint) and is_binary(label) do
    label = label |> String.trim() |> then(&if(&1 == "", do: nil, else: &1))

    cond do
      label && String.length(label) > PushSubscription.label_max() ->
        {:error, :too_long}

      sub = Repo.get_by(PushSubscription, endpoint: endpoint) ->
        sub |> Ecto.Changeset.change(label: label) |> Repo.update()

      true ->
        {:error, :not_found}
    end
  end

  def set_label(_endpoint, _label), do: {:error, :not_found}

  @doc """
  Turn off the public notifications of a browser. Returns `:ok` when its subscription is
  gone, or `:kept` when the device still gets the Postfach: then only its categories are
  cleared, and the browser must keep its subscription.
  """
  def unsubscribe(endpoint) do
    case Repo.get_by(PushSubscription, endpoint: endpoint) do
      %PushSubscription{user_id: user_id} = sub when not is_nil(user_id) ->
        sub |> Ecto.Changeset.change(categories: [], tester: false) |> Repo.update!()
        :kept

      _ ->
        Repo.delete_all(from s in PushSubscription, where: s.endpoint == ^endpoint)
        :ok
    end
  end

  @doc """
  Make this browser's subscription one of the user's Postfach devices. A browser has
  exactly one subscription per site, so a device already subscribed to Termine or news
  keeps those; a new one starts without categories. Knowing the endpoint proves the
  device; the caller must have checked the user's session. A device that changes hands
  moves to the new user. Staff are not subject to the public capacity limit.
  """
  def link_device(user, params, opts \\ [])

  def link_device(%User{id: user_id}, %{"endpoint" => endpoint} = params, opts) do
    if valid_push_endpoint?(endpoint) do
      attrs = %{
        "endpoint" => endpoint,
        "keys_p256dh" => get_in(params, ["keys", "p256dh"]),
        "keys_auth" => get_in(params, ["keys", "auth"])
      }

      (Repo.get_by(PushSubscription, endpoint: endpoint) || %PushSubscription{})
      |> PushSubscription.changeset(attrs)
      |> Ecto.Changeset.put_change(:user_id, user_id)
      |> put_device(opts[:user_agent])
      |> Repo.insert_or_update()
    else
      {:error, :invalid_endpoint}
    end
  end

  def link_device(_user, _params, _opts), do: {:error, :invalid_endpoint}

  @doc "The user's Postfach devices, newest first."
  def list_user_devices(%User{id: user_id}) do
    Repo.all(
      from s in PushSubscription, where: s.user_id == ^user_id, order_by: [desc: s.inserted_at]
    )
  end

  @doc """
  Stop telling this device about the Postfach. Only the user's own devices; one that
  also has public categories keeps them. Idempotent.
  """
  def unlink_device(%User{id: user_id}, id) do
    with {:ok, id} <- Ecto.UUID.cast(id),
         %PushSubscription{} = sub <- Repo.get_by(PushSubscription, id: id, user_id: user_id) do
      if sub.categories == [] do
        Repo.delete(sub)
      else
        sub |> Ecto.Changeset.change(user_id: nil) |> Repo.update()
      end
    else
      _ -> {:error, :not_found}
    end
  end

  @doc "Deletes devices with no owner and no categories left. Returns how many."
  def prune_orphans do
    {count, _} =
      Repo.delete_all(
        from s in PushSubscription,
          where: is_nil(s.user_id) and fragment("cardinality(?) = 0", s.categories)
      )

    count
  end

  @doc "Number of stored (active) push subscriptions."
  def count_subscriptions, do: Repo.aggregate(PushSubscription, :count, :id)

  @doc "All subscriptions for the admin overview, most-errored first."
  def list_subscriptions do
    Repo.all(from s in PushSubscription, order_by: [desc: s.error_count, desc: s.last_used])
  end

  @doc "Delete one subscription by id (admin overview). Idempotent."
  def delete_subscription(id) do
    case Repo.get(PushSubscription, id) do
      nil -> {:error, :not_found}
      sub -> Repo.delete(sub)
    end
  end

  @doc """
  Send an ad-hoc push composed by an admin. `category` is `"termine"`, `"news"`,
  `"all"` (every subscription, regardless of category) or `"tester"` (only devices
  flagged as test receivers). `payload` is a map with `title`, `body`, and `url`.
  """
  def send_manual(category, %{} = payload) when category in @categories,
    do: notify(category, payload)

  def send_manual("all", %{} = payload), do: notify_all(payload)

  def send_manual("tester", %{} = payload),
    do: send_to(from(s in PushSubscription, where: s.tester), payload)

  def send_manual(_category, _payload), do: {:error, :invalid_category}

  @doc """
  Send a notification to all subscribers of `category`. `payload` is a map with
  `title`, `body`, and `url`. Expired subscriptions are pruned. Runs the sends
  concurrently; safe to call from a Task.
  """
  def notify(category, %{} = payload) when category in @categories do
    from(s in PushSubscription, where: fragment("? = ANY(?)", ^category, s.categories))
    |> send_to(payload)
  end

  @doc """
  Send a notification to all of a user's Postfach devices. Returns how many took it, so
  the caller can fall back to mail on 0.
  """
  def notify_user(%User{id: user_id}, %{} = payload) do
    message = Jason.encode!(payload)

    from(s in PushSubscription, where: s.user_id == ^user_id)
    |> Repo.all()
    |> Task.async_stream(&send_one(&1, message), max_concurrency: 10, on_timeout: :kill_task)
    |> Enum.count(&(&1 == {:ok, true}))
  end

  # Send to everyone who subscribed to something (admin "all" broadcast). A device that
  # only gets the Postfach never asked for club news.
  defp notify_all(%{} = payload) do
    from(s in PushSubscription, where: fragment("cardinality(?) > 0", s.categories))
    |> send_to(payload)
  end

  defp send_to(query, payload) do
    message = Jason.encode!(payload)

    query
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
      false
    end
  end

  # Whether the push service took the message.
  defp do_send(sub, message) do
    json =
      Jason.encode!(%{
        "endpoint" => sub.endpoint,
        "keys" => %{"p256dh" => sub.keys_p256dh, "auth" => sub.keys_auth}
      })

    case sender().(json, message) do
      {:error, :expired} ->
        Repo.delete(sub)
        false

      {:error, reason} ->
        Logger.warning("Web push failed for #{sub.endpoint}: #{inspect(reason)}")

        sub
        |> Ecto.Changeset.change(
          error_count: sub.error_count + 1,
          last_error_at: DateTime.utc_now(:second)
        )
        |> Repo.update()

        false

      _ok ->
        sub
        |> Ecto.Changeset.change(
          last_used: DateTime.utc_now(:second),
          error_count: 0,
          last_error_at: nil
        )
        |> Repo.update()

        true
    end
  rescue
    e ->
      Logger.warning("Web push error for #{sub.endpoint}: #{inspect(e)}")
      false
  end

  # Tests set `config :bbh, Bbh.Notifications, sender: fun`; nothing else should.
  defp sender do
    Application.get_env(:bbh, __MODULE__, [])[:sender] || (&WebPushElixir.send_notification/2)
  end

  defp normalize_categories(cats) when is_list(cats), do: Enum.filter(cats, &(&1 in @categories))
  defp normalize_categories(_), do: @categories
end
