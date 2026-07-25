defmodule Bbh.CalendarShareTest do
  use Bbh.DataCase, async: true

  alias Bbh.Calendar
  alias Bbh.Calendar.CalendarShare
  alias Bbh.Repo

  import Bbh.CalendarFixtures
  import Bbh.AccountsFixtures
  import Swoosh.TestAssertions

  defp at(offset_days) do
    DateTime.utc_now() |> DateTime.add(offset_days, :day) |> DateTime.truncate(:second)
  end

  describe "create_share/3" do
    test "returns a plaintext token and stores only its hash" do
      user = user_fixture()

      assert {:ok, {plaintext, share}} =
               Calendar.create_share("vorstand", %{recipient_label: "a@example.com"}, user)

      assert is_binary(plaintext)
      assert share.calendar == "vorstand"
      assert share.recipient_label == "a@example.com"
      assert share.created_by_id == user.id

      # The stored token is the SHA-256 hash of the raw bytes, never the plaintext.
      assert {:ok, hash} = CalendarShare.hash_token(plaintext)
      assert share.token == hash
      refute share.token == plaintext
    end

    test "rejects an unknown calendar" do
      assert {:error, changeset} = Calendar.create_share("nonexistent", %{}, nil)
      assert "ist kein gültiger Kalender" in errors_on(changeset).calendar
    end

    test "allows a nil creator (e.g. system-generated)" do
      assert {:ok, {_plain, share}} = Calendar.create_share("offiziere", %{}, nil)
      assert is_nil(share.created_by_id)
    end
  end

  describe "verify_share_token/1" do
    test "returns the share for a valid token and stamps last_used_at" do
      {:ok, {plaintext, share}} = Calendar.create_share("vorstand", %{}, nil)
      assert is_nil(share.last_used_at)

      assert {:ok, verified} = Calendar.verify_share_token(plaintext)
      assert verified.id == share.id
      assert verified.last_used_at

      # Persisted, not just returned.
      assert Repo.get!(CalendarShare, share.id).last_used_at
    end

    test "rejects a revoked token" do
      {:ok, {plaintext, share}} = Calendar.create_share("vorstand", %{}, nil)
      {:ok, _} = Calendar.revoke_share(share.id)

      assert Calendar.verify_share_token(plaintext) == :error
    end

    test "rejects an expired token" do
      {:ok, {plaintext, _share}} =
        Calendar.create_share("vorstand", %{expires_at: at(-1)}, nil)

      assert Calendar.verify_share_token(plaintext) == :error
    end

    test "accepts a token whose expiry is still in the future" do
      {:ok, {plaintext, _share}} =
        Calendar.create_share("vorstand", %{expires_at: at(30)}, nil)

      assert {:ok, _verified} = Calendar.verify_share_token(plaintext)
    end

    test "rejects an unknown token" do
      {:ok, {_plaintext, _share}} = Calendar.create_share("vorstand", %{}, nil)
      {other, _hash} = CalendarShare.build_token()

      assert Calendar.verify_share_token(other) == :error
    end

    test "rejects a malformed token" do
      assert Calendar.verify_share_token("not base64!!") == :error
    end
  end

  describe "revoke_share/1" do
    test "sets revoked_at and is idempotent" do
      {:ok, {_plaintext, share}} = Calendar.create_share("vorstand", %{}, nil)

      assert {:ok, revoked} = Calendar.revoke_share(share.id)
      assert revoked.revoked_at

      # Revoking again keeps it revoked (does not error).
      assert {:ok, again} = Calendar.revoke_share(share.id)
      assert again.revoked_at
    end
  end

  describe "rotate_share_token/1" do
    test "invalidates the old token and returns a fresh working one for the same share" do
      {:ok, {old, share}} = Calendar.create_share("vorstand", %{recipient_label: "a@b.com"}, nil)

      assert {:ok, {new, rotated}} = Calendar.rotate_share_token(share)
      assert new != old
      assert rotated.id == share.id
      assert Calendar.verify_share_token(old) == :error
      assert {:ok, _} = Calendar.verify_share_token(new)
    end

    test "resets last_used_at so the fresh token reads as never used" do
      {:ok, {old, share}} = Calendar.create_share("vorstand", %{}, nil)
      {:ok, _} = Calendar.verify_share_token(old)
      assert Repo.reload!(share).last_used_at

      {:ok, {_new, rotated}} = Calendar.rotate_share_token(Repo.reload!(share))
      assert is_nil(rotated.last_used_at)
    end

    test "keeps calendar, recipient and expiry" do
      {:ok, {_old, share}} =
        Calendar.create_share("offiziere", %{recipient_label: "x@y.com", expires_at: at(30)}, nil)

      {:ok, {_new, rotated}} = Calendar.rotate_share_token(share)
      assert rotated.calendar == "offiziere"
      assert rotated.recipient_label == "x@y.com"
      assert rotated.expires_at == share.expires_at
    end
  end

  describe "list_shares/1" do
    test "lists shares for a calendar, newest first" do
      {:ok, {_p1, first}} = Calendar.create_share("vorstand", %{recipient_label: "1"}, nil)
      {:ok, {_p2, second}} = Calendar.create_share("vorstand", %{recipient_label: "2"}, nil)
      {:ok, {_p3, _other}} = Calendar.create_share("offiziere", %{}, nil)

      ids = Calendar.list_shares("vorstand") |> Enum.map(& &1.id)
      assert second.id in ids
      assert first.id in ids
      assert length(ids) == 2
    end
  end

  describe "CalendarShare.emailable?/1" do
    test "accepts a well-formed address and rejects labels and partial addresses" do
      assert CalendarShare.emailable?("kassierer@example.com")
      refute CalendarShare.emailable?("Kassierer")
      refute CalendarShare.emailable?("foo@")
      refute CalendarShare.emailable?("@bar")
      refute CalendarShare.emailable?("foo@bar")
      refute CalendarShare.emailable?(nil)
    end
  end

  describe "deliver_share_link/2" do
    test "emails the link when the recipient label is an address" do
      {:ok, {_plain, share}} =
        Calendar.create_share("vorstand", %{recipient_label: "kassierer@example.com"}, nil)

      assert {:ok, _email} =
               Calendar.deliver_share_link(share, "https://example.com/kalender/geteilt/abc")

      assert_email_sent(fn email ->
        assert email.subject =~ "Vorstand"
        assert {_, "kassierer@example.com"} = hd(email.to)
        assert email.text_body =~ "https://example.com/kalender/geteilt/abc"
      end)
    end

    test "skips delivery when the label is not an email" do
      {:ok, {_plain, share}} =
        Calendar.create_share("vorstand", %{recipient_label: "Kassierer"}, nil)

      assert Calendar.deliver_share_link(share, "https://example.com/x") == :skip
      assert_no_email_sent()
    end
  end

  describe "shared_calendar_events/1" do
    test "returns only published events of the target calendar" do
      published = event_fixture(calendar: "vorstand", status: "published", starts_at: at(3))
      _draft = event_fixture(calendar: "vorstand", status: "draft", starts_at: at(4))
      _other_cal = event_fixture(calendar: "offiziere", status: "published", starts_at: at(5))
      _public = event_fixture(starts_at: at(6))

      events = Calendar.shared_calendar_events("vorstand")
      assert Enum.map(events, & &1.id) == [published.id]
    end

    test "orders events chronologically" do
      later = event_fixture(calendar: "vorstand", status: "published", starts_at: at(10))
      sooner = event_fixture(calendar: "vorstand", status: "published", starts_at: at(2))

      events = Calendar.shared_calendar_events("vorstand")
      assert Enum.map(events, & &1.id) == [sooner.id, later.id]
    end
  end
end
