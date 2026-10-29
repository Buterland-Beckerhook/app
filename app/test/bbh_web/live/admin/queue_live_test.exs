defmodule BbhWeb.Admin.QueueLiveTest do
  use BbhWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import Bbh.AccountsFixtures

  alias Bbh.Tickets.Queue

  setup :register_and_log_in_admin

  test "lists the queues and creates a new one", %{conn: conn} do
    {:ok, _lv, html} = live(conn, ~p"/admin/postfaecher")
    assert html =~ "vorstand@buterland-beckerhook.de"
    assert html =~ "Mitgliedsanträge"

    {:ok, lv, _} = live(conn, ~p"/admin/postfaecher/neu")

    lv
    |> form("#queue-form",
      queue: %{
        key: "social",
        label: "Social Media",
        inbound_address: "insta@buterland-beckerhook.de",
        in_contact_form: "true"
      }
    )
    |> render_submit()

    assert %{label: "Social Media", in_contact_form: true} = Queue.get("social")
    assert render(lv) =~ "insta@buterland-beckerhook.de"
  end

  test "edits a queue but never its key", %{conn: conn} do
    {:ok, lv, html} = live(conn, ~p"/admin/postfaecher/vorstand")
    refute html =~ ~s(name="queue[key]")

    lv |> form("#queue-form", queue: %{signature: "Der Vorstand"}) |> render_submit()
    assert Queue.signature("vorstand") == "Der Vorstand"
  end

  test "the fixed queues have no delete button", %{conn: conn} do
    {:ok, lv, _} = live(conn, ~p"/admin/postfaecher")
    refute has_element?(lv, ~s|[phx-value-key="info"]|)
    refute render(lv) =~ ~s|"key":"info"|
  end

  test "is admin-only", %{conn: _conn} do
    conn = log_in_user(build_conn(), user_fixture())
    assert {:error, {:redirect, %{to: "/admin"}}} = live(conn, ~p"/admin/postfaecher")
  end
end
