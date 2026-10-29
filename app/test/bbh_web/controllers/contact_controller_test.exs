defmodule BbhWeb.ContactControllerTest do
  # async: false — the altcha describe mutates the global :bbh, :altcha_hmac_key env.
  use BbhWeb.ConnCase

  import Swoosh.TestAssertions

  @valid %{
    "name" => "Erika Musterfrau",
    "email" => "erika@example.com",
    "message" => "Ich hätte eine Frage."
  }

  # A form_ts token signed as if issued 10s ago, so the min-fill-time check passes.
  defp past_token(seconds_ago \\ 10) do
    Phoenix.Token.sign(BbhWeb.Endpoint, "contact_form", System.os_time(:second) - seconds_ago)
  end

  # Valid params plus a plausibly-timed form token (the human-timing gate).
  defp human_params(extra \\ %{}) do
    @valid |> Map.put("form_ts", past_token()) |> Map.merge(extra)
  end

  test "GET /kontakt renders the form", %{conn: conn} do
    assert conn |> get(~p"/kontakt") |> html_response(200) =~ "Kontakt"
  end

  test "GET /kontakt points to the privacy policy instead of asking for consent", %{conn: conn} do
    doc = conn |> get(~p"/kontakt") |> html_response(200) |> LazyHTML.from_document()

    assert doc |> LazyHTML.query("#privacy-notice a[href='/datenschutz']") |> Enum.any?()
    assert doc |> LazyHTML.query("input[name=privacy]") |> Enum.empty?()
  end

  describe "POST /kontakt (altcha disabled)" do
    test "sends the message and redirects on valid input", %{conn: conn} do
      conn = post(conn, ~p"/kontakt", human_params())

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

    test "rejects a too-short message", %{conn: conn} do
      html =
        conn |> post(~p"/kontakt", human_params(%{"message" => "Hi"})) |> html_response(200)

      assert html =~ "zu kurz"
      assert_no_email_sent()
    end

    test "rejects a filled honeypot as spam", %{conn: conn} do
      conn = post(conn, ~p"/kontakt", human_params(%{"website" => "http://spam.example"}))

      assert html_response(conn, 200) =~ "Spam-Schutz"
      assert_no_email_sent()
    end

    test "rejects a submission that arrives too fast", %{conn: conn} do
      # form_ts issued "now" -> below the minimum human fill time.
      params = @valid |> Map.put("form_ts", past_token(0))
      conn = post(conn, ~p"/kontakt", params)

      assert html_response(conn, 200) =~ "Spam-Schutz"
      assert_no_email_sent()
    end

    test "rejects a submission with a missing/forged timestamp as spam", %{conn: conn} do
      conn = post(conn, ~p"/kontakt", Map.put(@valid, "form_ts", "forged"))

      assert html_response(conn, 200) =~ "Spam-Schutz"
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
      # Passes honeypot + timing so the altcha layer is the one that trips.
      conn = post(conn, ~p"/kontakt", human_params(%{"altcha" => "garbage"}))

      assert html_response(conn, 200) =~ "Spam-Schutz"
      assert_no_email_sent()
    end
  end

  describe "with the Postfach (TICKETS_ENABLED)" do
    setup do
      Application.put_env(:bbh, :tickets_enabled, true)
      on_exit(fn -> Application.delete_env(:bbh, :tickets_enabled) end)
    end

    test "offers the queues, preselected via ?an=", %{conn: conn} do
      html = conn |> get(~p"/kontakt?an=vorstand") |> html_response(200)
      assert html =~ ~s|<option value="vorstand" selected|
      refute html =~ ~s|value="webmaster"|
      refute html =~ ~s|value="mitgliedschaft"|
    end

    test "creates a ticket in the chosen queue and sends no mail", %{conn: conn} do
      conn = post(conn, ~p"/kontakt", human_params(%{"an" => "offiziere"}))

      assert redirected_to(conn) == ~p"/kontakt"
      assert Phoenix.Flash.get(conn.assigns.flash, :info) =~ "eingegangen"
      assert_no_email_sent()

      [ticket] = Bbh.Repo.all(Bbh.Tickets.Ticket)
      assert ticket.queue == "offiziere"
      assert ticket.kind == "contact"
      assert ticket.status == "new"

      admin = Bbh.Accounts.Scope.for_user(Bbh.AccountsFixtures.admin_user_fixture())
      {:ok, loaded} = Bbh.Tickets.get_ticket(admin, ticket.number)
      assert loaded.subject == "Ich hätte eine Frage."
      assert loaded.requester_name == "Erika Musterfrau"
      refute Map.has_key?(loaded.payload || %{}, "client_ip")
    end

    test "falls back to the default queue for one the form does not offer", %{conn: conn} do
      post(conn, ~p"/kontakt", human_params(%{"an" => "mitgliedschaft"}))
      assert [%{queue: "info"}] = Bbh.Repo.all(Bbh.Tickets.Ticket)
    end
  end
end
