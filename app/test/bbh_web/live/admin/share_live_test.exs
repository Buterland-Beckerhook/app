defmodule BbhWeb.Admin.ShareLiveTest do
  use BbhWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import Bbh.AccountsFixtures
  import Bbh.CalendarFixtures

  alias Bbh.Accounts
  alias Bbh.Calendar

  defp calendar_editor_fixture(calendars) do
    user = user_fixture()
    {:ok, user} = Accounts.update_user_role(user, "calendar_editor")
    {:ok, user} = Accounts.update_user_calendars(user, calendars)
    user
  end

  describe "access" do
    test "redirects an anonymous visitor to the login page", %{conn: conn} do
      assert {:error, {:redirect, %{to: "/users/log-in"}}} = live(conn, ~p"/admin/termine/teilen")
    end

    test "an admin can open the share page", %{conn: conn} do
      conn = log_in_user(conn, admin_user_fixture())
      {:ok, _lv, html} = live(conn, ~p"/admin/termine/teilen")
      assert html =~ "Kalender teilen"
    end
  end

  describe "creating a share" do
    setup %{conn: conn}, do: %{conn: log_in_user(conn, admin_user_fixture())}

    test "shows the link and a QR code after creating", %{conn: conn} do
      {:ok, lv, _html} = live(conn, ~p"/admin/termine/teilen")

      html =
        lv
        |> form("#share-form", share: %{calendar: "vorstand", recipient_label: "kassierer"})
        |> render_submit()

      assert html =~ "/kalender/geteilt/"
      # QR code rendered as inline SVG.
      assert html =~ "<svg"
      # The new share appears in the list.
      assert html =~ "kassierer"
    end

    test "stores a date expiry as end-of-day so the link is valid through that date",
         %{conn: conn} do
      {:ok, lv, _html} = live(conn, ~p"/admin/termine/teilen")

      lv
      |> form("#share-form",
        share: %{calendar: "vorstand", recipient_label: "z", expires_at: "2030-01-15"}
      )
      |> render_submit()

      share = Calendar.list_shares("vorstand") |> hd()
      assert %DateTime{hour: 23, minute: 59, second: 59} = share.expires_at
      assert DateTime.to_date(share.expires_at) == ~D[2030-01-15]
    end

    test "persists the share", %{conn: conn} do
      {:ok, lv, _html} = live(conn, ~p"/admin/termine/teilen")

      lv
      |> form("#share-form", share: %{calendar: "offiziere", recipient_label: "adjutant"})
      |> render_submit()

      assert [share] = Calendar.list_shares("offiziere")
      assert share.recipient_label == "adjutant"
    end

    test "reports emailing the link when notify is checked and the label is an address",
         %{conn: conn} do
      {:ok, lv, _html} = live(conn, ~p"/admin/termine/teilen")

      html =
        lv
        |> form("#share-form",
          share: %{calendar: "vorstand", recipient_label: "kassierer@example.com", notify: "true"}
        )
        |> render_submit()

      assert html =~ "per E-Mail"
    end
  end

  describe "revoking a share" do
    setup %{conn: conn}, do: %{conn: log_in_user(conn, admin_user_fixture())}

    test "marks the share as revoked and drops the revoke affordance", %{conn: conn} do
      share = calendar_share_fixture(calendar: "vorstand", recipient_label: "x")
      {:ok, lv, _html} = live(conn, ~p"/admin/termine/teilen")

      assert has_element?(lv, "#revoke-#{share.id}")
      html = lv |> element("#revoke-#{share.id}") |> render_click()

      # The button is gone (share no longer active) and the status badge flips.
      refute has_element?(lv, "#revoke-#{share.id}")
      assert html =~ "Widerrufen"
      assert Calendar.list_shares("vorstand") |> hd() |> Map.get(:revoked_at)
    end
  end

  describe "resending a share" do
    setup %{conn: conn}, do: %{conn: log_in_user(conn, admin_user_fixture())}

    test "rotates the token, kills the old link, re-emails and shows the new one",
         %{conn: conn} do
      {:ok, {old, share}} =
        Calendar.create_share("vorstand", %{recipient_label: "kassierer@example.com"}, nil)

      {:ok, lv, _html} = live(conn, ~p"/admin/termine/teilen")
      html = lv |> element("#resend-#{share.id}") |> render_click()

      assert html =~ "per E-Mail"
      assert html =~ "/kalender/geteilt/"
      assert Calendar.verify_share_token(old) == :error
    end

    test "regenerates the link without emailing when the recipient is not an address",
         %{conn: conn} do
      {:ok, {old, share}} =
        Calendar.create_share("vorstand", %{recipient_label: "Kassierer"}, nil)

      {:ok, lv, _html} = live(conn, ~p"/admin/termine/teilen")
      html = lv |> element("#resend-#{share.id}") |> render_click()

      assert html =~ "ungültig"
      assert html =~ "/kalender/geteilt/"
      assert Calendar.verify_share_token(old) == :error
    end

    test "refuses to resend a revoked share and does not rotate its token", %{conn: conn} do
      {:ok, {old, share}} = Calendar.create_share("vorstand", %{recipient_label: "a@b.com"}, nil)
      {:ok, _} = Calendar.revoke_share(share.id)

      {:ok, lv, _html} = live(conn, ~p"/admin/termine/teilen")
      html = render_click(lv, "resend", %{"id" => share.id})

      assert html =~ "nicht mehr aktiv"
      # The stored hash is unchanged — no new (dead) token was minted.
      {:ok, old_hash} = Bbh.Calendar.CalendarShare.hash_token(old)
      assert Bbh.Repo.get!(Bbh.Calendar.CalendarShare, share.id).token == old_hash
    end
  end

  describe "authorization" do
    test "a calendar editor sees only their granted calendars as options", %{conn: conn} do
      conn = log_in_user(conn, calendar_editor_fixture(["vorstand"]))
      {:ok, _lv, html} = live(conn, ~p"/admin/termine/teilen")

      assert html =~ "Vorstand"
      refute html =~ "Offiziere"
    end

    test "a calendar editor cannot create a share for a non-granted calendar", %{conn: conn} do
      conn = log_in_user(conn, calendar_editor_fixture(["vorstand"]))
      {:ok, lv, _html} = live(conn, ~p"/admin/termine/teilen")

      # Submit a non-granted calendar directly (bypassing the select's options) to
      # exercise the server-side authorization guard.
      html =
        lv
        |> element("#share-form")
        |> render_submit(%{"share" => %{"calendar" => "offiziere", "recipient_label" => "y"}})

      assert html =~ "Berechtigung"
      assert Calendar.list_shares("offiziere") == []
    end

    test "a calendar editor cannot rotate a share outside their grant", %{conn: conn} do
      # A share on a calendar this editor does NOT manage.
      {:ok, {old, offi_share}} =
        Calendar.create_share("offiziere", %{recipient_label: "a@b.com"}, nil)

      conn = log_in_user(conn, calendar_editor_fixture(["vorstand"]))
      {:ok, lv, _html} = live(conn, ~p"/admin/termine/teilen")

      # Force the event past the DOM (the button is never rendered for this editor).
      render_click(lv, "resend", %{"id" => offi_share.id})

      # The out-of-grant share is untouched — its original link still works.
      assert {:ok, _} = Calendar.verify_share_token(old)
    end
  end
end
