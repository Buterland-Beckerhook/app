defmodule BbhWeb.PushDialogTest do
  use BbhWeb.ConnCase, async: true

  test "public pages carry the push settings dialog, without the admin switch", %{conn: conn} do
    html = conn |> get(~p"/verein") |> html_response(200)

    assert html =~ ~s(id="push-dialog")
    assert html =~ ~s(name="push-category" value="termine")
    assert html =~ ~s(name="push-category" value="news")
    refute html =~ ~s(id="push-tester")
  end

  describe "for admins" do
    setup :register_and_log_in_admin

    test "the dialog offers the test-device switch", %{conn: conn} do
      html = conn |> get(~p"/verein") |> html_response(200)
      assert html =~ ~s(id="push-tester")
    end
  end

  describe "for editors" do
    setup :register_and_log_in_user

    test "the dialog has no test-device switch", %{conn: conn} do
      html = conn |> get(~p"/verein") |> html_response(200)
      refute html =~ ~s(id="push-tester")
    end
  end
end
