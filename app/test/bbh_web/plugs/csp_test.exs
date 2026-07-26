defmodule BbhWeb.Plugs.CSPTest do
  use BbhWeb.ConnCase

  # These pin the one guarantee the front-end code leans on: every bit of JavaScript in
  # this app is either the nonced bundle or something it loaded, never an inline `on*`
  # attribute. Nothing else can catch a regression here — ExUnit renders HTML but runs
  # no JavaScript, so a template that grew an `onclick=` would keep passing every other
  # test while doing nothing in production.

  defp policy(conn) do
    conn
    |> get_resp_header("content-security-policy")
    |> List.first()
    |> to_string()
    |> String.split("; ")
    |> Map.new(fn directive ->
      [name | values] = String.split(directive, " ")
      {name, values}
    end)
  end

  test "scripts run by nonce and strict-dynamic only", %{conn: conn} do
    directives = conn |> get(~p"/") |> policy()

    # The two properties that matter, not the exact list — adding a legitimate source
    # later should not break a test that is not about that.
    assert Enum.any?(directives["script-src"], &String.starts_with?(&1, "'nonce-"))
    assert "'strict-dynamic'" in directives["script-src"]

    # The load-bearing absence: with 'unsafe-inline' an inline handler would run, and
    # the delegated-listener convention in assets/js/app.js would quietly rot.
    refute "'unsafe-inline'" in directives["script-src"]
  end

  test "the nonce is fresh per request and matches the script tag", %{conn: conn} do
    html = conn |> get(~p"/") |> html_response(200)

    nonce =
      Regex.run(~r/<script[^>]*src="\/assets\/js\/app\.js"[^>]*nonce="([^"]+)"/, html)
      |> Enum.at(1)

    assert nonce

    # A reused nonce would let an attacker who once saw the page inline a matching
    # script tag into any later injection point.
    second = conn |> get(~p"/") |> html_response(200)
    refute second =~ ~s(nonce="#{nonce}")
  end

  test "the rest of the policy stays closed", %{conn: conn} do
    directives = conn |> get(~p"/") |> policy()

    assert directives["default-src"] == ["'self'"]
    assert directives["object-src"] == ["'none'"]
    assert directives["base-uri"] == ["'self'"]
    assert directives["frame-ancestors"] == ["'self'"]
    assert directives["form-action"] == ["'self'"]
  end
end
