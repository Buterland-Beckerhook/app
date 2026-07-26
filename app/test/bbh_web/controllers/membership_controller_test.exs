defmodule BbhWeb.MembershipControllerTest do
  # async: false — the altcha describe mutates the global :bbh, :altcha_hmac_key env.
  use BbhWeb.ConnCase

  import Swoosh.TestAssertions

  @valid %{
    "nachname" => "Musterfrau",
    "vorname" => "Erika",
    "plz" => "48599",
    "ort" => "Gronau",
    "strasse" => "Musterweg 1",
    "geburtsdatum" => "1988-04-12",
    "email" => "erika@example.com",
    "kontoinhaber" => "Erika Musterfrau",
    "iban" => "DE89370400440532013000",
    "bic" => "COBADEFFXXX",
    "kreditinstitut" => "Commerzbank",
    "sepa" => "true",
    "satzung" => "true",
    "datenspeicherung" => "true",
    "privacy" => "true"
  }

  # A form_ts token signed as if issued 10s ago, so the min-fill-time check passes.
  defp past_token(seconds_ago \\ 10) do
    Phoenix.Token.sign(BbhWeb.Endpoint, "membership_form", System.os_time(:second) - seconds_ago)
  end

  # Valid params plus a plausibly-timed form token (the human-timing gate).
  defp human_params(extra \\ %{}) do
    @valid |> Map.put("form_ts", past_token()) |> Map.merge(extra)
  end

  test "GET /verein/mitglied-werden renders the form", %{conn: conn} do
    assert conn |> get(~p"/verein/mitglied-werden") |> html_response(200) =~ "Mitglied werden"
  end

  describe "POST /verein/mitglied-werden (altcha disabled)" do
    test "sends both mails and redirects on valid input", %{conn: conn} do
      conn = post(conn, ~p"/verein/mitglied-werden", human_params())

      assert redirected_to(conn) == ~p"/verein/mitglied-werden"
      assert Phoenix.Flash.get(conn.assigns.flash, :info) =~ "gesendet"
      assert_email_sent(fn email -> assert email.subject =~ "Erika Musterfrau" end)

      assert_email_sent(fn email ->
        assert email.to == [{"Erika Musterfrau", "erika@example.com"}]
      end)
    end

    test "re-renders with validation errors on invalid input", %{conn: conn} do
      html = conn |> post(~p"/verein/mitglied-werden", %{"nachname" => ""}) |> html_response(200)
      assert html =~ "Bitte geben Sie Ihren Namen an."
      assert html =~ "Bitte geben Sie eine gültige E-Mail-Adresse an."
      assert_no_email_sent()
    end

    test "rejects an invalid IBAN", %{conn: conn} do
      html =
        conn
        |> post(~p"/verein/mitglied-werden", human_params(%{"iban" => "DE00"}))
        |> html_response(200)

      assert html =~ "gültige IBAN"
      assert_no_email_sent()
    end

    test "rejects a filled honeypot as spam", %{conn: conn} do
      conn =
        post(
          conn,
          ~p"/verein/mitglied-werden",
          human_params(%{"website" => "http://spam.example"})
        )

      assert html_response(conn, 200) =~ "Spam-Schutz"
      assert_no_email_sent()
    end

    test "rejects a submission that arrives too fast", %{conn: conn} do
      params = @valid |> Map.put("form_ts", past_token(0))
      conn = post(conn, ~p"/verein/mitglied-werden", params)

      assert html_response(conn, 200) =~ "Spam-Schutz"
      assert_no_email_sent()
    end

    test "rejects a missing/forged timestamp as spam", %{conn: conn} do
      conn = post(conn, ~p"/verein/mitglied-werden", Map.put(@valid, "form_ts", "forged"))

      assert html_response(conn, 200) =~ "Spam-Schutz"
      assert_no_email_sent()
    end
  end

  describe "POST /verein/mitglied-werden (altcha enabled)" do
    setup do
      Application.put_env(:bbh, :altcha_hmac_key, "membership-test-key")
      on_exit(fn -> Application.delete_env(:bbh, :altcha_hmac_key) end)
      :ok
    end

    test "rejects a missing/invalid altcha solution", %{conn: conn} do
      conn = post(conn, ~p"/verein/mitglied-werden", human_params(%{"altcha" => "garbage"}))

      assert html_response(conn, 200) =~ "Spam-Schutz"
      assert_no_email_sent()
    end
  end
end
