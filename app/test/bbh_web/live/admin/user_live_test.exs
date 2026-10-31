defmodule BbhWeb.Admin.UserLiveTest do
  use BbhWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import Bbh.AccountsFixtures

  alias Bbh.Accounts

  setup :register_and_log_in_admin

  test "lists users including the current admin", %{conn: conn, user: admin} do
    other = user_fixture()
    {:ok, _lv, html} = live(conn, ~p"/admin/benutzer")

    assert html =~ admin.email
    assert html =~ other.email
  end

  test "shows a passkey column reflecting enrollment", %{conn: conn} do
    enrolled = user_fixture()
    _without = user_fixture()

    # Scope the check to the users table (`#users` tbody) so page chrome like the
    # base64 session token can't produce a false "ja". 2FA is off for everyone,
    # so within the table a "ja" can only come from the passkey column.
    {:ok, lv, _html} = live(conn, ~p"/admin/benutzer")
    assert render(lv) =~ "Passkey"
    refute has_element?(lv, "#users", "ja")

    # Enrolling a passkey flips the column to "ja".
    passkey_fixture(enrolled)
    {:ok, lv, _html} = live(conn, ~p"/admin/benutzer")
    assert has_element?(lv, "#users", "ja")
  end

  test "invites a new user", %{conn: conn} do
    {:ok, lv, _html} = live(conn, ~p"/admin/benutzer")
    email = "neu#{System.unique_integer([:positive])}@example.com"

    html =
      lv
      |> form("#invite-form", user: %{email: email, role: "editor"})
      |> render_submit()

    assert html =~ "Einladung an #{email} gesendet"
    assert Accounts.get_user_by_email(email)
  end

  test "promotes an editor to admin via the role select", %{conn: conn} do
    editor = user_fixture()
    {:ok, lv, _html} = live(conn, ~p"/admin/benutzer")

    # Drive the actual per-row form so the event name + param shape are exercised.
    lv
    |> element("#role-#{editor.id}")
    |> render_change(%{"user_id" => editor.id, "role" => "admin"})

    assert Accounts.get_user!(editor.id).role == "admin"
  end

  test "refuses to change the current admin's own role", %{conn: conn, user: admin} do
    {:ok, lv, _html} = live(conn, ~p"/admin/benutzer")

    html = render_hook(lv, "set_role", %{"user_id" => admin.id, "role" => "editor"})

    assert html =~ "eigene Rolle"
    assert Accounts.get_user!(admin.id).role == "admin"
  end

  test "refuses to delete the current admin's own account", %{conn: conn, user: admin} do
    {:ok, lv, _html} = live(conn, ~p"/admin/benutzer")

    html = render_click(lv, "delete", %{"id" => admin.id})

    assert html =~ "eigene Konto"
    assert Accounts.get_user!(admin.id)
  end

  test "deletes another user", %{conn: conn} do
    other = user_fixture()
    {:ok, lv, _html} = live(conn, ~p"/admin/benutzer")

    render_click(lv, "delete", %{"id" => other.id})

    assert_raise Ecto.NoResultsError, fn -> Accounts.get_user!(other.id) end
  end

  test "logs another user out on all devices", %{conn: conn} do
    other = user_fixture()
    token = Accounts.generate_user_session_token(other)
    {:ok, lv, _html} = live(conn, ~p"/admin/benutzer")

    html = render_click(lv, "logout_all", %{"id" => other.id})

    assert html =~ "von allen Geräten abgemeldet"
    refute Accounts.get_user_by_session_token(token)
  end

  describe "login log" do
    test "shows a user's entries, newest first", %{conn: conn} do
      other = user_fixture()

      Bbh.Accounts.AuthLog.record(%{
        user: other,
        event: "totp_failed",
        method: "magic_link_totp",
        ip: "203.0.113.7",
        user_agent: "Firefox/140"
      })

      {:ok, lv, _html} = live(conn, ~p"/admin/benutzer")
      assert has_element?(lv, ~s|a[href="/admin/benutzer/#{other.id}/anmeldungen"]|)

      {:ok, _lv, html} = live(conn, ~p"/admin/benutzer/#{other.id}/anmeldungen")
      assert html =~ other.email
      assert html =~ "Falscher 2FA-Code"
      assert html =~ "Anmeldelink + 2FA"
      assert html =~ "203.0.113.7"
      assert html =~ "Firefox/140"
    end

    test "is admin-only", %{conn: conn} do
      editor = user_fixture()
      conn = log_in_user(conn, editor)

      assert {:error, {:redirect, %{to: "/admin"}}} =
               live(conn, ~p"/admin/benutzer/#{editor.id}/anmeldungen")
    end
  end

  test "grants Postfach queues per user", %{conn: conn, user: admin} do
    other = user_fixture()
    {:ok, lv, _html} = live(conn, ~p"/admin/benutzer")

    lv
    |> element("#queues-#{other.id}")
    |> render_change(%{"user_id" => other.id, "queues" => ["", "info", "vorstand"]})

    assert Bbh.Tickets.Grants.list_queue_keys(other) == ["info", "vorstand"]

    assert Bbh.Repo.get_by!(Bbh.Tickets.Grant, user_id: other.id, queue_key: "info").granted_by_id ==
             admin.id
  end

  describe "privilege changes reach open tabs" do
    test "a role change disconnects the user's sockets but keeps the session", %{conn: conn} do
      other = user_fixture()
      token = watch_session(other)
      {:ok, lv, _html} = live(conn, ~p"/admin/benutzer")

      lv
      |> element("#role-#{other.id}")
      |> render_change(%{"user_id" => other.id, "role" => "admin"})

      assert_receive %Phoenix.Socket.Broadcast{event: "disconnect"}
      assert Accounts.get_user_by_session_token(token)
    end

    test "a queue grant change disconnects the user's sockets", %{conn: conn} do
      other = user_fixture()
      watch_session(other)
      {:ok, lv, _html} = live(conn, ~p"/admin/benutzer")

      lv
      |> element("#queues-#{other.id}")
      |> render_change(%{"user_id" => other.id, "queues" => ["", "info"]})

      assert_receive %Phoenix.Socket.Broadcast{event: "disconnect"}
    end

    test "a calendar grant change disconnects the user's sockets", %{conn: conn} do
      other = user_fixture()
      watch_session(other)
      {:ok, lv, _html} = live(conn, ~p"/admin/benutzer")
      [calendar | _] = Bbh.Calendar.Event.calendars()

      lv
      |> element("#cals-#{other.id}")
      |> render_change(%{"user_id" => other.id, "calendars" => ["", calendar]})

      assert_receive %Phoenix.Socket.Broadcast{event: "disconnect"}
      assert Accounts.get_user!(other.id).calendars == [calendar]
    end

    test "deleting a user disconnects their sockets", %{conn: conn} do
      other = user_fixture()
      watch_session(other)
      {:ok, lv, _html} = live(conn, ~p"/admin/benutzer")

      render_click(lv, "delete", %{"id" => other.id})

      assert_receive %Phoenix.Socket.Broadcast{event: "disconnect"}
    end

    test "a refused role change disconnects nobody", %{conn: conn, user: admin} do
      watch_session(admin)
      {:ok, lv, _html} = live(conn, ~p"/admin/benutzer")

      render_hook(lv, "set_role", %{"user_id" => admin.id, "role" => "editor"})

      refute_receive %Phoenix.Socket.Broadcast{event: "disconnect"}
    end
  end

  test "offers the role Nur Postfach", %{conn: conn} do
    {:ok, _lv, html} = live(conn, ~p"/admin/benutzer")
    assert html =~ "Nur Postfach"
  end

  # Subscribes to the live-socket topic of a fresh session of `user`.
  defp watch_session(user) do
    token = Accounts.generate_user_session_token(user)
    BbhWeb.Endpoint.subscribe("users_sessions:#{Base.url_encode64(token)}")
    token
  end

  describe "resetting second factors" do
    test "wipes the factors and shows the one-time code once", %{conn: conn} do
      user = user_fixture()
      passkey_fixture(user)
      {:ok, lv, _html} = live(conn, ~p"/admin/benutzer")

      html = render_click(lv, "reset_factors", %{"id" => user.id})

      assert [_, code] = Regex.run(~r/([A-HJ-NP-Z2-9]{4}-[A-HJ-NP-Z2-9]{4})/, html)
      assert html =~ "persönlich oder telefonisch"
      refute Accounts.Passkeys.has_passkey?(user)
      assert Accounts.valid_factor_reset_code?(user, code)

      assert [_] = Bbh.Repo.all_by(Accounts.AuthEvent, user_id: user.id, event: "factors_reset")

      refute render_click(lv, "dismiss_reset_code", %{}) =~ code
    end

    test "is not offered for the own account", %{conn: conn, user: admin} do
      {:ok, lv, _html} = live(conn, ~p"/admin/benutzer")

      assert render_click(lv, "reset_factors", %{"id" => admin.id}) =~
               "kann nicht zurückgesetzt werden"

      refute Accounts.factor_reset_pending?(admin)
    end
  end
end
