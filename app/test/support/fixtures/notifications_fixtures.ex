defmodule Bbh.NotificationsFixtures do
  @moduledoc "Test helpers for creating Web Push subscriptions."

  alias Bbh.Notifications.PushSubscription
  alias Bbh.Repo

  @doc """
  Insert a push subscription directly (bypassing `Bbh.Notifications.subscribe/1`,
  so tests can create rows with arbitrary endpoints — including untrusted ones for
  the SSRF-prune path).
  """
  def push_subscription_fixture(attrs \\ %{}) do
    attrs =
      Enum.into(attrs, %{
        endpoint: "https://fcm.googleapis.com/fcm/send/#{System.unique_integer([:positive])}",
        keys_p256dh: "p256dh-key",
        keys_auth: "auth-key",
        categories: ["news", "termine"]
      })

    %PushSubscription{} |> PushSubscription.changeset(attrs) |> Repo.insert!()
  end
end
