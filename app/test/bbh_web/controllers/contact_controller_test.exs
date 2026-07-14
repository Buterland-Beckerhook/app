defmodule BbhWeb.ContactControllerTest do
  # async: false — the altcha describe mutates the global :bbh, :altcha_hmac_key env.
  use BbhWeb.ConnCase

  import Swoosh.TestAssertions

  @valid %{
    "name" => "Erika Musterfrau",
    "email" => "erika@example.com",
    "message" => "Ich hätte eine Frage.",
    "privacy" => "true"
  }

  test "GET /kontakt renders the form", %{conn: conn} do
    assert conn |> get(~p"/kontakt") |> html_response(200) =~ "Kontakt"
  end

  describe "POST /kontakt (altcha disabled)" do
    test "sends the message and redirects on valid input", %{conn: conn} do
      conn = post(conn, ~p"/kontakt", @valid)

      assert redirected_to(conn) == ~p"/kontakt"
      assert Phoenix.Flash.get(conn.assigns.flash, :info) =~ "gesendet"
      assert_email_sent(fn email -> assert email.subject =~ "Erika Musterfrau" end)
    end

    test "re-renders with validation errors on invalid input", %{conn: conn} do
      html = conn |> post(~p"/kontakt", %{"name" => ""}) |> html_response(200)
      # Must show the actual field errors, not merely re-render the page shell.
      assert html =~ "Bitte geben Sie Ihren Namen an."
      assert html =~ "Bitte geben Sie eine gültige E-Mail-Adresse an."
      assert_no_email_sent()
    end
  end

  describe "POST /kontakt (altcha enabled)" do
    setup do
      Application.put_env(:bbh, :altcha_hmac_key, "contact-test-key")
      on_exit(fn -> Application.delete_env(:bbh, :altcha_hmac_key) end)
      :ok
    end

    test "rejects a missing/invalid altcha solution", %{conn: conn} do
      conn = post(conn, ~p"/kontakt", Map.put(@valid, "altcha", "garbage"))

      assert html_response(conn, 200) =~ "Spam-Schutz"
      assert_no_email_sent()
    end
  end
end
