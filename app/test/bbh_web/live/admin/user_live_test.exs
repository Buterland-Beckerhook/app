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
end
