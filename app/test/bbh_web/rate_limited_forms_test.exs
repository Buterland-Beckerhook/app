defmodule BbhWeb.RateLimitedFormsTest do
  # async: false — turns the (globally disabled in test) rate limiter on.
  use BbhWeb.ConnCase

  import Phoenix.LiveViewTest
  import Ecto.Query
  import Bbh.AccountsFixtures

  alias BbhWeb.RateLimit

  setup %{conn: conn} do
    previous = Application.get_env(:bbh, RateLimit, [])
    Application.put_env(:bbh, RateLimit, Keyword.put(previous, :enabled, true))
    on_exit(fn -> Application.put_env(:bbh, RateLimit, previous) end)

    # A fresh client IP per test, so buckets never carry over between tests.
    n = System.unique_integer([:positive])
    ip = "10.#{rem(div(n, 65_536), 256)}.#{rem(div(n, 256), 256)}.#{rem(n, 256)}"
    %{conn: put_req_header(conn, "x-forwarded-for", ip)}
  end

  defp form_ts(salt),
    do: Phoenix.Token.sign(BbhWeb.Endpoint, salt, System.os_time(:second) - 10)

  describe "contact form" do
    defp contact(conn) do
      post(conn, ~p"/kontakt", %{
        "name" => "Erika Musterfrau",
        "email" => "erika@example.com",
        "message" => "Ich hätte eine Frage.",
        "form_ts" => form_ts("contact_form")
      })
    end

    test "accepts five messages an hour per address, then refuses", %{conn: conn} do
      for _ <- 1..5, do: assert(redirected_to(contact(conn)) == ~p"/kontakt")

      html = conn |> contact() |> html_response(200)
      assert html =~ "Zu viele Anfragen"
      # The visitor's text is kept for a later try.
      assert html =~ "Ich hätte eine Frage."
    end

    test "invalid submissions do not count", %{conn: conn} do
      for _ <- 1..10, do: post(conn, ~p"/kontakt", %{"name" => ""})

      assert redirected_to(contact(conn)) == ~p"/kontakt"
    end
  end

  describe "membership form" do
    defp apply_for_membership(conn) do
      post(conn, ~p"/verein/mitglied-werden", %{
        "vorname" => "Erika",
        "nachname" => "Musterfrau",
        "geburtsdatum" => "1990-01-01",
        "strasse" => "Musterweg 1",
        "plz" => "12345",
        "ort" => "Musterstadt",
        "email" => "erika@example.com",
        "kontoinhaber" => "Erika Musterfrau",
        "iban" => "DE89370400440532013000",
        "bic" => "COBADEFFXXX",
        "kreditinstitut" => "Commerzbank",
        "sepa" => "true",
        "form_ts" => form_ts("membership_form")
      })
    end

    test "accepts ten applications an hour per address, then refuses", %{conn: conn} do
      for _ <- 1..10, do: assert(redirected_to(apply_for_membership(conn)))

      assert conn |> apply_for_membership() |> html_response(200) =~ "Zu viele Anfragen"
    end
  end

  describe "magic link" do
    defp request_link(conn, email) do
      {:ok, lv, _html} = live(conn, ~p"/users/log-in")

      lv
      |> form("#login_form_magic", user: %{email: email})
      |> render_submit()
    end

    test "sends at most three links per address, with an unchanged answer", %{conn: conn} do
      user = user_fixture()

      # Four requests stay under the per-IP limit (5), so only the per-email one bites.
      for _ <- 1..4 do
        {:ok, _lv, html} =
          conn |> request_link(user.email) |> follow_redirect(conn, ~p"/users/log-in")

        assert html =~ "Falls die Adresse bei uns hinterlegt ist"
      end

      assert Bbh.Repo.aggregate(
               from(t in Bbh.Accounts.UserToken,
                 where: t.user_id == ^user.id and t.context == "login"
               ),
               :count
             ) == 3
    end
  end
end
