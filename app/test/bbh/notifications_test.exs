defmodule Bbh.NotificationsTest do
  # async: false — notify/2 spawns tasks that touch the DB (needs shared sandbox).
  use Bbh.DataCase

  alias Bbh.Notifications
  alias Bbh.Notifications.PushSubscription

  import Bbh.NotificationsFixtures

  describe "valid_push_endpoint?/1" do
    test "accepts known push-service hosts" do
      assert Notifications.valid_push_endpoint?("https://fcm.googleapis.com/fcm/send/abc")
      assert Notifications.valid_push_endpoint?("https://web.push.apple.com/x")
      assert Notifications.valid_push_endpoint?("https://updates.push.services.mozilla.com/x")
    end

    test "accepts allowed host suffixes" do
      assert Notifications.valid_push_endpoint?("https://foo.notify.windows.com/x")
      assert Notifications.valid_push_endpoint?("https://bar.push.services.mozilla.com/x")
    end

    test "rejects non-https, unknown hosts, and non-binaries" do
      refute Notifications.valid_push_endpoint?("http://fcm.googleapis.com/x")
      refute Notifications.valid_push_endpoint?("https://169.254.169.254/latest/meta-data")
      refute Notifications.valid_push_endpoint?("https://evil.example.com/x")
      refute Notifications.valid_push_endpoint?("ftp://fcm.googleapis.com/x")
      refute Notifications.valid_push_endpoint?(nil)
      refute Notifications.valid_push_endpoint?(123)
    end
  end

  describe "subscribe/1" do
    @valid_params %{
      "endpoint" => "https://fcm.googleapis.com/fcm/send/tok",
      "keys" => %{"p256dh" => "pk", "auth" => "ak"},
      "categories" => ["news"]
    }

    test "creates a subscription for a trusted endpoint" do
      assert {:ok, %PushSubscription{} = sub} = Notifications.subscribe(@valid_params)
      assert sub.endpoint == "https://fcm.googleapis.com/fcm/send/tok"
      assert sub.categories == ["news"]
    end

    test "upserts by endpoint (no duplicate rows)" do
      {:ok, _} = Notifications.subscribe(@valid_params)
      {:ok, _} = Notifications.subscribe(%{@valid_params | "categories" => ["termine"]})

      assert Repo.aggregate(PushSubscription, :count) == 1

      assert %{categories: ["termine"]} =
               Repo.get_by(PushSubscription, endpoint: @valid_params["endpoint"])
    end

    test "defaults to all categories when none are given" do
      params = Map.delete(@valid_params, "categories")
      assert {:ok, sub} = Notifications.subscribe(params)
      assert Enum.sort(sub.categories) == ["news", "termine"]
    end

    test "drops unknown categories" do
      assert {:ok, sub} =
               Notifications.subscribe(%{@valid_params | "categories" => ["news", "bogus"]})

      assert sub.categories == ["news"]
    end

    test "rejects an untrusted endpoint (SSRF guard)" do
      params = %{@valid_params | "endpoint" => "https://169.254.169.254/x"}
      assert {:error, :invalid_endpoint} = Notifications.subscribe(params)
      assert Repo.aggregate(PushSubscription, :count) == 0
    end

    test "rejects params without an endpoint" do
      assert {:error, :invalid_endpoint} = Notifications.subscribe(%{"keys" => %{}})
    end
  end

  describe "unsubscribe/1" do
    test "removes the row for the given endpoint" do
      sub = push_subscription_fixture()
      assert :ok = Notifications.unsubscribe(sub.endpoint)
      refute Repo.get(PushSubscription, sub.id)
    end
  end

  describe "count_subscriptions/0" do
    test "counts stored subscriptions" do
      assert Notifications.count_subscriptions() == 0
      push_subscription_fixture()
      push_subscription_fixture()
      assert Notifications.count_subscriptions() == 2
    end
  end

  describe "notify/2" do
    test "prunes stored subscriptions whose endpoint is no longer trusted" do
      bogus =
        push_subscription_fixture(
          endpoint: "https://169.254.169.254/internal",
          categories: ["news"]
        )

      # No trusted subscribers → no outbound HTTP; only the SSRF-prune path runs.
      assert :ok == Notifications.notify("news", %{title: "T", body: "B", url: "https://x"})
      refute Repo.get(PushSubscription, bogus.id)
    end

    test "raises for an unknown category (only known callers)" do
      assert_raise FunctionClauseError, fn ->
        Notifications.notify("nope", %{title: "T", body: "B", url: "https://x"})
      end
    end
  end

  describe "subscription_status/1 and set_tester/2" do
    @push_endpoint "https://fcm.googleapis.com/fcm/send/status"

    setup do
      {:ok, sub} =
        Notifications.subscribe(%{
          "endpoint" => @push_endpoint,
          "keys" => %{"p256dh" => "pk", "auth" => "ak"},
          "categories" => ["termine"]
        })

      %{sub: sub}
    end

    test "reports the stored categories and tester flag" do
      assert {:ok, %{categories: ["termine"], tester: false}} =
               Notifications.subscription_status(@push_endpoint)

      assert :error = Notifications.subscription_status("https://fcm.googleapis.com/x")
      assert :error = Notifications.subscription_status(nil)
    end

    test "set_tester/2 flags the device; re-subscribing keeps the flag" do
      assert {:ok, %{tester: true}} = Notifications.set_tester(@push_endpoint, true)

      {:ok, _} =
        Notifications.subscribe(%{
          "endpoint" => @push_endpoint,
          "keys" => %{"p256dh" => "pk", "auth" => "ak"},
          "categories" => ["news"],
          "tester" => false
        })

      assert {:ok, %{categories: ["news"], tester: true}} =
               Notifications.subscription_status(@push_endpoint)

      assert {:error, :not_found} = Notifications.set_tester("https://fcm.googleapis.com/x", true)
    end
  end

  describe "subscribe/2 device description and set_label/2" do
    @device_endpoint "https://fcm.googleapis.com/fcm/send/device"
    @params %{
      "endpoint" => @device_endpoint,
      "keys" => %{"p256dh" => "pk", "auth" => "ak"},
      "categories" => ["termine"]
    }
    @android_firefox "Mozilla/5.0 (Android 14; Mobile; rv:131.0) Gecko/131.0 Firefox/131.0"

    test "stores a short device description, not the raw User-Agent" do
      {:ok, sub} = Notifications.subscribe(@params, user_agent: @android_firefox)
      assert sub.device == "Firefox · Android"
    end

    test "a re-subscribe without a User-Agent keeps the description" do
      {:ok, _} = Notifications.subscribe(@params, user_agent: @android_firefox)
      {:ok, sub} = Notifications.subscribe(@params)
      assert sub.device == "Firefox · Android"
    end

    test "the device can't be set through params" do
      {:ok, sub} = Notifications.subscribe(Map.put(@params, "device", "Fake"))
      assert sub.device == nil
    end

    test "set_label/2 names the device, trims, and clears on blank" do
      {:ok, _} = Notifications.subscribe(@params)

      assert {:ok, %{label: "Roberts iPhone"}} =
               Notifications.set_label(@device_endpoint, "  Roberts iPhone ")

      assert {:ok, %{label: "Roberts iPhone"}} =
               Notifications.subscription_status(@device_endpoint)

      # A re-subscribe (e.g. changed categories) keeps the name.
      {:ok, _} = Notifications.subscribe(Map.put(@params, "label", "Other"))

      assert {:ok, %{label: "Roberts iPhone"}} =
               Notifications.subscription_status(@device_endpoint)

      assert {:ok, %{label: nil}} = Notifications.set_label(@device_endpoint, "   ")
    end

    test "set_label/2 rejects overlong names and unknown endpoints" do
      {:ok, _} = Notifications.subscribe(@params)

      too_long = String.duplicate("x", PushSubscription.label_max() + 1)
      assert {:error, :too_long} = Notifications.set_label(@device_endpoint, too_long)

      assert {:error, :not_found} =
               Notifications.set_label("https://fcm.googleapis.com/x", "Name")

      assert {:error, :not_found} = Notifications.set_label(nil, "Name")
    end
  end
end
