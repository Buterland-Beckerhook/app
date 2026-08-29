defmodule BbhWeb.OAuthControllerTest do
  use BbhWeb.ConnCase, async: true

  alias Bbh.OAuth
  alias BbhWeb.MCP

  @redirect "http://localhost:9999/callback"

  setup %{conn: conn} do
    {:ok, client} =
      OAuth.register_client(%{
        "client_name" => "Test Client",
        "redirect_uris" => [@redirect]
      })

    %{conn: put_req_header(conn, "content-type", "application/json"), client: client}
  end

  ## Helpers

  defp pkce do
    verifier = 32 |> :crypto.strong_rand_bytes() |> Base.url_encode64(padding: false)
    challenge = :sha256 |> :crypto.hash(verifier) |> Base.url_encode64(padding: false)
    {verifier, challenge}
  end

  defp authorize_params(client, challenge, overrides \\ %{}) do
    Map.merge(
      %{
        "client_id" => client.client_id,
        "redirect_uri" => @redirect,
        "response_type" => "code",
        "code_challenge" => challenge,
        "code_challenge_method" => "S256",
        "state" => "opaque-state",
        "resource" => MCP.resource_uri()
      },
      overrides
    )
  end

  # The `code` a successful consent hands back through the redirect.
  defp code_from(conn) do
    conn
    |> redirected_to()
    |> URI.parse()
    |> Map.fetch!(:query)
    |> URI.decode_query()
  end

  describe "discovery" do
    test "protected-resource metadata points at this app", %{conn: conn} do
      # Both paths RFC 9728 allows; clients probe them in different orders.
      for path <- [
            ~p"/.well-known/oauth-protected-resource",
            ~p"/.well-known/oauth-protected-resource/mcp"
          ] do
        body = conn |> get(path) |> json_response(200)

        assert body["resource"] == MCP.resource_uri()
        assert body["authorization_servers"] == [MCP.issuer()]
        assert body["scopes_supported"] == ["mcp:read", "mcp:write"]
      end
    end

    test "authorization-server metadata advertises what we actually enforce", %{conn: conn} do
      body = conn |> get(~p"/.well-known/oauth-authorization-server") |> json_response(200)

      assert body["issuer"] == MCP.issuer()
      assert body["authorization_endpoint"] =~ "/oauth/authorize"
      assert body["token_endpoint"] =~ "/oauth/token"
      assert body["registration_endpoint"] =~ "/oauth/register"
      assert body["code_challenge_methods_supported"] == ["S256"]
      assert body["token_endpoint_auth_methods_supported"] == ["none"]
      assert body["grant_types_supported"] == ["authorization_code", "refresh_token"]
      assert body["authorization_response_iss_parameter_supported"] == true
    end

    test "metadata needs no credential", %{conn: conn} do
      assert conn
             |> put_req_header("authorization", "Bearer nonsense")
             |> get(~p"/.well-known/oauth-authorization-server")
             |> json_response(200)
    end
  end

  describe "POST /oauth/register" do
    test "registers a client and returns its id", %{conn: conn} do
      body =
        conn
        |> post(~p"/oauth/register", %{
          "client_name" => "Claude",
          "redirect_uris" => ["https://claude.ai/api/mcp/auth_callback"]
        })
        |> json_response(201)

      assert body["client_id"]
      assert body["client_name"] == "Claude"
      assert body["token_endpoint_auth_method"] == "none"
      assert body["grant_types"] == ["authorization_code", "refresh_token"]
      refute body["client_secret"]
    end

    test "rejects a redirect URI it cannot vouch for", %{conn: conn} do
      body =
        conn
        |> post(~p"/oauth/register", %{"redirect_uris" => ["http://evil.test/cb"]})
        |> json_response(400)

      assert body["error"] == "invalid_redirect_uri"
    end
  end

  describe "GET /oauth/authorize" do
    test "sends an unauthenticated visitor through the app's own login", %{
      conn: conn,
      client: client
    } do
      {_verifier, challenge} = pkce()

      conn = get(conn, ~p"/oauth/authorize?#{authorize_params(client, challenge)}")

      assert redirected_to(conn) =~ "log-in"
    end

    test "renders consent for a logged-in user", %{conn: conn, client: client} do
      %{conn: conn} = register_and_log_in_user(%{conn: conn})
      {_verifier, challenge} = pkce()

      html =
        conn
        |> get(~p"/oauth/authorize?#{authorize_params(client, challenge)}")
        |> html_response(200)

      assert html =~ "Test Client"
      assert html =~ "Erlauben"
    end

    test "refuses to redirect anywhere for an unknown client", %{conn: conn} do
      %{conn: conn} = register_and_log_in_user(%{conn: conn})

      conn =
        get(conn, ~p"/oauth/authorize?#{%{"client_id" => "nope", "redirect_uri" => @redirect}}")

      # An unregistered client has no address we may hand an error to, so the message
      # stays here rather than being forwarded to an attacker-chosen URI.
      assert html_response(conn, 400) =~ "nicht registriert"
    end

    test "refuses to redirect to an unregistered URI", %{conn: conn, client: client} do
      %{conn: conn} = register_and_log_in_user(%{conn: conn})
      {_verifier, challenge} = pkce()

      params = authorize_params(client, challenge, %{"redirect_uri" => "https://evil.test/cb"})
      conn = get(conn, ~p"/oauth/authorize?#{params}")

      assert html_response(conn, 400) =~ "Rücksprungadresse"
    end

    test "reports a non-S256 challenge to the client, not to the user", %{
      conn: conn,
      client: client
    } do
      %{conn: conn} = register_and_log_in_user(%{conn: conn})
      {_verifier, challenge} = pkce()

      params = authorize_params(client, challenge, %{"code_challenge_method" => "plain"})
      query = conn |> get(~p"/oauth/authorize?#{params}") |> code_from()

      assert query["error"] == "invalid_request"
      assert query["state"] == "opaque-state"
      assert query["iss"] == MCP.issuer()
    end

    test "reports a missing challenge", %{conn: conn, client: client} do
      %{conn: conn} = register_and_log_in_user(%{conn: conn})

      params =
        client
        |> authorize_params("ignored")
        |> Map.drop(["code_challenge", "code_challenge_method"])

      assert conn |> get(~p"/oauth/authorize?#{params}") |> code_from() |> Map.get("error") ==
               "invalid_request"
    end

    test "reports a foreign audience", %{conn: conn, client: client} do
      %{conn: conn} = register_and_log_in_user(%{conn: conn})
      {_verifier, challenge} = pkce()

      params = authorize_params(client, challenge, %{"resource" => "https://elsewhere.test/mcp"})

      assert conn |> get(~p"/oauth/authorize?#{params}") |> code_from() |> Map.get("error") ==
               "invalid_target"
    end

    test "reports an unsupported response type", %{conn: conn, client: client} do
      %{conn: conn} = register_and_log_in_user(%{conn: conn})
      {_verifier, challenge} = pkce()

      params = authorize_params(client, challenge, %{"response_type" => "token"})

      assert conn |> get(~p"/oauth/authorize?#{params}") |> code_from() |> Map.get("error") ==
               "unsupported_response_type"
    end
  end

  describe "POST /oauth/authorize" do
    setup %{conn: conn} do
      register_and_log_in_user(%{conn: conn})
    end

    test "a denial redirects back with access_denied", %{conn: conn, client: client} do
      {_verifier, challenge} = pkce()
      params = Map.put(authorize_params(client, challenge), "decision", "deny")

      query = conn |> post(~p"/oauth/authorize", params) |> code_from()

      assert query["error"] == "access_denied"
      assert query["state"] == "opaque-state"
      refute query["code"]
    end

    test "re-validates the hidden fields instead of trusting them", %{
      conn: conn,
      client: client
    } do
      {_verifier, challenge} = pkce()

      # A crafted form can swap the redirect URI after the user has read the original one,
      # so the POST validates from scratch rather than trusting its own markup.
      params =
        client
        |> authorize_params(challenge, %{"redirect_uri" => "https://evil.test/cb"})
        |> Map.put("decision", "approve")

      assert html_response(post(conn, ~p"/oauth/authorize", params), 400) =~ "Rücksprungadresse"
    end

    test "a missing decision is not an approval", %{conn: conn, client: client} do
      {_verifier, challenge} = pkce()

      query =
        conn |> post(~p"/oauth/authorize", authorize_params(client, challenge)) |> code_from()

      assert query["error"] == "invalid_request"
      refute query["code"]
    end
  end

  describe "the full flow" do
    setup %{conn: conn} do
      %{conn: browser, user: user} = register_and_log_in_user(%{conn: conn})
      %{browser: browser, user: user, api: build_conn()}
    end

    test "authorize → token → /mcp → refresh", %{
      browser: browser,
      api: api,
      client: client,
      user: user
    } do
      {verifier, challenge} = pkce()

      params = Map.put(authorize_params(client, challenge), "decision", "approve")
      query = browser |> post(~p"/oauth/authorize", params) |> code_from()

      assert query["code"]
      assert query["state"] == "opaque-state"
      # RFC 9207: which authorization server answered, so a client talking to several
      # cannot be tricked into redeeming this code at another one.
      assert query["iss"] == MCP.issuer()

      tokens =
        api
        |> post(~p"/oauth/token", %{
          "grant_type" => "authorization_code",
          "code" => query["code"],
          "client_id" => client.client_id,
          "redirect_uri" => @redirect,
          "code_verifier" => verifier,
          "resource" => MCP.resource_uri()
        })
        |> json_response(200)

      assert tokens["token_type"] == "Bearer"
      assert tokens["expires_in"] == OAuth.access_validity_in_seconds()

      # The token that came out of the flow must actually open the endpoint it was
      # minted for — the whole point of the exercise.
      assert %{"result" => %{"tools" => tools}} = mcp(tokens["access_token"], "tools/list")
      assert tools != []

      refreshed =
        api
        |> post(~p"/oauth/token", %{
          "grant_type" => "refresh_token",
          "refresh_token" => tokens["refresh_token"],
          "client_id" => client.client_id
        })
        |> json_response(200)

      assert refreshed["refresh_token"] != tokens["refresh_token"]
      assert %{"result" => _} = mcp(refreshed["access_token"], "ping")

      assert [connection] = OAuth.list_connections(user)
      assert connection.client_name == "Test Client"
    end

    test "a token response must not be cached", %{browser: browser, api: api, client: client} do
      {verifier, challenge} = pkce()
      params = Map.put(authorize_params(client, challenge), "decision", "approve")
      query = browser |> post(~p"/oauth/authorize", params) |> code_from()

      conn =
        post(api, ~p"/oauth/token", %{
          "grant_type" => "authorization_code",
          "code" => query["code"],
          "client_id" => client.client_id,
          "redirect_uri" => @redirect,
          "code_verifier" => verifier
        })

      assert get_resp_header(conn, "cache-control") == ["no-store"]
    end

    test "a code is single-use and its replay kills the tokens it made", %{
      browser: browser,
      api: api,
      client: client
    } do
      {verifier, challenge} = pkce()
      params = Map.put(authorize_params(client, challenge), "decision", "approve")
      query = browser |> post(~p"/oauth/authorize", params) |> code_from()

      request = %{
        "grant_type" => "authorization_code",
        "code" => query["code"],
        "client_id" => client.client_id,
        "redirect_uri" => @redirect,
        "code_verifier" => verifier
      }

      tokens = api |> post(~p"/oauth/token", request) |> json_response(200)
      body = api |> post(~p"/oauth/token", request) |> json_response(400)

      assert body["error"] == "invalid_grant"
      assert %{"error" => _} = mcp(tokens["access_token"], "tools/list")
    end

    test "the wrong verifier yields the same error as a wrong code", %{
      browser: browser,
      api: api,
      client: client
    } do
      {_verifier, challenge} = pkce()
      params = Map.put(authorize_params(client, challenge), "decision", "approve")
      query = browser |> post(~p"/oauth/authorize", params) |> code_from()

      wrong_verifier =
        api
        |> post(~p"/oauth/token", %{
          "grant_type" => "authorization_code",
          "code" => query["code"],
          "client_id" => client.client_id,
          "redirect_uri" => @redirect,
          "code_verifier" => "wrong"
        })
        |> json_response(400)

      unknown_code =
        api
        |> post(~p"/oauth/token", %{
          "grant_type" => "authorization_code",
          "code" => "nonexistent",
          "client_id" => client.client_id,
          "redirect_uri" => @redirect,
          "code_verifier" => "wrong"
        })
        |> json_response(400)

      # Identical bodies on purpose: a client guessing must not learn which half it got
      # right.
      assert wrong_verifier == unknown_code
      assert wrong_verifier["error"] == "invalid_grant"
    end

    test "a token minted for another audience cannot be requested", %{
      browser: browser,
      api: api,
      client: client
    } do
      {verifier, challenge} = pkce()
      params = Map.put(authorize_params(client, challenge), "decision", "approve")
      query = browser |> post(~p"/oauth/authorize", params) |> code_from()

      body =
        api
        |> post(~p"/oauth/token", %{
          "grant_type" => "authorization_code",
          "code" => query["code"],
          "client_id" => client.client_id,
          "redirect_uri" => @redirect,
          "code_verifier" => verifier,
          "resource" => "https://elsewhere.test/mcp"
        })
        |> json_response(400)

      assert body["error"] == "invalid_target"
    end
  end

  describe "POST /oauth/token" do
    test "refuses a grant type this server does not issue", %{conn: conn} do
      body =
        conn
        |> post(~p"/oauth/token", %{"grant_type" => "client_credentials"})
        |> json_response(400)

      assert body["error"] == "unsupported_grant_type"
    end

    test "refuses a request without a grant type", %{conn: conn} do
      assert conn |> post(~p"/oauth/token", %{}) |> json_response(400) |> Map.get("error") ==
               "invalid_request"
    end
  end

  # A JSON-RPC call to /mcp with a bearer token, on its own connection.
  defp mcp(access_token, method) do
    build_conn()
    |> put_req_header("content-type", "application/json")
    |> put_req_header("authorization", "Bearer #{access_token}")
    |> post(~p"/mcp", Jason.encode!(%{jsonrpc: "2.0", id: 1, method: method}))
    |> then(fn conn ->
      case conn.status do
        200 -> Jason.decode!(conn.resp_body)
        401 -> %{"error" => "unauthorized"}
      end
    end)
  end
end
