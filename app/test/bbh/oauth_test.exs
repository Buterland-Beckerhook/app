defmodule Bbh.OAuthTest do
  use Bbh.DataCase, async: true

  import Bbh.AccountsFixtures

  alias Bbh.ApiTokens
  alias Bbh.ApiTokens.ApiToken
  alias Bbh.OAuth
  alias Bbh.OAuth.AuthorizationCode
  alias Bbh.Repo

  @resource "https://example.test/mcp"
  @redirect "http://localhost:9999/callback"

  setup do
    {:ok, client} =
      OAuth.register_client(%{
        "client_name" => "Test Client",
        "redirect_uris" => [@redirect]
      })

    %{user: user_fixture(), client: client}
  end

  ## Helpers

  defp pkce do
    verifier = 32 |> :crypto.strong_rand_bytes() |> Base.url_encode64(padding: false)
    challenge = :sha256 |> :crypto.hash(verifier) |> Base.url_encode64(padding: false)
    {verifier, challenge}
  end

  defp issue_code(client, user, challenge, opts \\ []) do
    {:ok, code} =
      OAuth.create_authorization_code(client, user, %{
        redirect_uri: Keyword.get(opts, :redirect_uri, @redirect),
        code_challenge: challenge,
        resource: Keyword.get(opts, :resource, @resource),
        scopes: Keyword.get(opts, :scopes, ["mcp:read", "mcp:write"])
      })

    code
  end

  defp exchange(code, verifier, client, overrides \\ []) do
    OAuth.exchange_code(
      Keyword.merge(
        [
          code: code,
          client_id: client.client_id,
          redirect_uri: @redirect,
          code_verifier: verifier,
          resource: @resource
        ],
        overrides
      )
    )
  end

  describe "register_client/1" do
    test "generates its own client_id and ignores one the caller supplies" do
      {:ok, client} =
        OAuth.register_client(%{
          "client_id" => "attacker-chosen",
          "redirect_uris" => ["https://example.test/cb"]
        })

      refute client.client_id == "attacker-chosen"
      assert String.starts_with?(client.client_id, "bbh-")
    end

    test "accepts https anywhere and http only on loopback" do
      for uri <- ["https://claude.ai/api/mcp/auth_callback", "http://127.0.0.1:1234/cb"] do
        assert {:ok, _} = OAuth.register_client(%{"redirect_uris" => [uri]})
      end
    end

    test "rejects a redirect URI an attacker could read" do
      for uri <- [
            # Plaintext to a remote host: the code would cross the network in the clear.
            "http://evil.test/cb",
            # A fragment is never sent to the server and so cannot be matched.
            "https://example.test/cb#frag",
            "not-a-uri",
            "javascript:alert(1)"
          ] do
        assert {:error, changeset} = OAuth.register_client(%{"redirect_uris" => [uri]})
        assert changeset.errors[:redirect_uris]
      end
    end

    test "requires at least one redirect URI" do
      # An empty list equals the schema default, so `cast/3` sees no change — the exact
      # input a change-driven validation would wave through.
      for attrs <- [%{"redirect_uris" => []}, %{}, %{"redirect_uris" => "not-a-list"}] do
        assert {:error, changeset} = OAuth.register_client(attrs)
        assert changeset.errors[:redirect_uris]
      end
    end

    test "refuses to be used as storage" do
      uris = for i <- 1..6, do: "http://localhost:#{9000 + i}/cb"

      assert {:error, changeset} = OAuth.register_client(%{"redirect_uris" => uris})
      assert changeset.errors[:redirect_uris]
    end

    test "keeps only scopes this server grants" do
      {:ok, client} =
        OAuth.register_client(%{
          "redirect_uris" => [@redirect],
          "scope" => "mcp:read admin:everything"
        })

      assert client.scopes == ["mcp:read"]
    end
  end

  describe "exchange_code/1" do
    test "issues a working access/refresh pair", %{user: user, client: client} do
      {verifier, challenge} = pkce()
      code = issue_code(client, user, challenge)

      assert {:ok, tokens} = exchange(code, verifier, client)
      assert tokens.token_type == "Bearer"
      assert tokens.expires_in == OAuth.access_validity_in_seconds()
      assert tokens.scope == "mcp:read mcp:write"

      # The access token must actually work against the audience it was minted for.
      assert {:ok, found, token} = ApiTokens.verify(tokens.access_token, @resource)
      assert found.id == user.id
      assert token.kind == "access"
      assert token.oauth_client_id == client.client_id
    end

    test "refuses a wrong PKCE verifier without spending the code", %{
      user: user,
      client: client
    } do
      {verifier, challenge} = pkce()
      code = issue_code(client, user, challenge)

      assert {:error, :invalid_grant} = exchange(code, "wrong-verifier", client)
      # A failed attempt must not lock the legitimate client out.
      assert {:ok, _tokens} = exchange(code, verifier, client)
    end

    test "refuses a redirect URI other than the one consented to", %{user: user, client: client} do
      {verifier, challenge} = pkce()
      code = issue_code(client, user, challenge)

      assert {:error, :invalid_grant} =
               exchange(code, verifier, client, redirect_uri: "http://localhost:9999/other")
    end

    test "refuses another client's attempt to redeem the code", %{user: user, client: client} do
      {:ok, other} = OAuth.register_client(%{"redirect_uris" => [@redirect]})
      {verifier, challenge} = pkce()
      code = issue_code(client, user, challenge)

      assert {:error, :invalid_grant} = exchange(code, verifier, other)
    end

    test "refuses a token request for a different audience", %{user: user, client: client} do
      {verifier, challenge} = pkce()
      code = issue_code(client, user, challenge)

      assert {:error, :invalid_target} =
               exchange(code, verifier, client, resource: "https://elsewhere.test/mcp")
    end

    test "inherits the audience when the token request omits it", %{user: user, client: client} do
      {verifier, challenge} = pkce()
      code = issue_code(client, user, challenge)

      assert {:ok, tokens} = exchange(code, verifier, client, resource: nil)
      assert {:ok, _user, token} = ApiTokens.verify(tokens.access_token, @resource)
      assert token.resource == @resource
    end

    test "refuses an expired code", %{user: user, client: client} do
      {verifier, challenge} = pkce()
      code = issue_code(client, user, challenge)
      expire_codes!()

      assert {:error, :invalid_grant} = exchange(code, verifier, client)
    end

    test "refuses an unknown or malformed code", %{client: client} do
      assert {:error, :invalid_grant} = exchange("nope", "verifier", client)
      assert {:error, :invalid_grant} = exchange("!!!not base64!!!", "verifier", client)
      assert {:error, :invalid_grant} = exchange(nil, "verifier", client)
    end

    test "replaying a spent code revokes every token that client holds", %{
      user: user,
      client: client
    } do
      {verifier, challenge} = pkce()
      code = issue_code(client, user, challenge)
      {:ok, tokens} = exchange(code, verifier, client)

      # A second redemption means the code leaked. The tokens it already produced must not
      # keep working.
      assert {:error, :invalid_grant} = exchange(code, verifier, client)
      assert {:error, :revoked} = ApiTokens.verify(tokens.access_token, @resource)
      assert {:error, :revoked} = ApiTokens.verify(tokens.refresh_token, @resource)
    end
  end

  describe "refresh/1" do
    setup %{user: user, client: client} do
      {verifier, challenge} = pkce()
      code = issue_code(client, user, challenge)
      {:ok, tokens} = exchange(code, verifier, client)
      %{tokens: tokens}
    end

    test "rotates the refresh token", %{tokens: tokens, client: client} do
      assert {:ok, fresh} =
               OAuth.refresh(
                 refresh_token: tokens.refresh_token,
                 client_id: client.client_id,
                 resource: @resource
               )

      refute fresh.refresh_token == tokens.refresh_token
      assert {:ok, _user, _token} = ApiTokens.verify(fresh.access_token, @resource)
      # The presented token is spent whether or not the client uses the new one.
      assert {:error, :revoked} = ApiTokens.verify(tokens.refresh_token, @resource)
    end

    test "replaying a rotated refresh token takes down the whole family", %{
      tokens: tokens,
      client: client
    } do
      {:ok, fresh} =
        OAuth.refresh(
          refresh_token: tokens.refresh_token,
          client_id: client.client_id,
          resource: @resource
        )

      assert {:error, :invalid_grant} =
               OAuth.refresh(
                 refresh_token: tokens.refresh_token,
                 client_id: client.client_id,
                 resource: @resource
               )

      # The tokens issued by the rotation are collateral, and that is the point: after a
      # replay we cannot tell the thief from the client.
      assert {:error, :revoked} = ApiTokens.verify(fresh.access_token, @resource)
    end

    test "inherits the audience when the refresh request omits it", %{
      tokens: tokens,
      client: client
    } do
      # `resource` is optional on a refresh; omitting it must keep the granted audience
      # rather than be read as a request for none.
      assert {:ok, fresh} =
               OAuth.refresh(refresh_token: tokens.refresh_token, client_id: client.client_id)

      assert {:ok, _user, token} = ApiTokens.verify(fresh.access_token, @resource)
      assert token.resource == @resource
    end

    test "refuses a refresh aimed at another audience", %{tokens: tokens, client: client} do
      assert {:error, :invalid_target} =
               OAuth.refresh(
                 refresh_token: tokens.refresh_token,
                 client_id: client.client_id,
                 resource: "https://elsewhere.test/mcp"
               )

      # A refused request must not have spent the token.
      assert {:ok, _fresh} =
               OAuth.refresh(refresh_token: tokens.refresh_token, client_id: client.client_id)
    end

    test "refuses another client's use of the refresh token", %{tokens: tokens} do
      {:ok, other} = OAuth.register_client(%{"redirect_uris" => [@redirect]})

      assert {:error, :invalid_grant} =
               OAuth.refresh(
                 refresh_token: tokens.refresh_token,
                 client_id: other.client_id,
                 resource: @resource
               )
    end

    test "refuses an access token presented as a refresh token", %{
      tokens: tokens,
      client: client
    } do
      assert {:error, :invalid_grant} =
               OAuth.refresh(
                 refresh_token: tokens.access_token,
                 client_id: client.client_id,
                 resource: @resource
               )
    end

    test "refuses a personal access token presented as a refresh token", %{
      user: user,
      client: client
    } do
      {:ok, pat, _} = ApiTokens.create_pat(user, "pat", ["mcp:read"])

      assert {:error, :invalid_grant} =
               OAuth.refresh(refresh_token: pat, client_id: client.client_id, resource: @resource)
    end
  end

  describe "connections" do
    test "lists a connected client and disconnects it", %{user: user, client: client} do
      {verifier, challenge} = pkce()
      code = issue_code(client, user, challenge)
      {:ok, tokens} = exchange(code, verifier, client)

      assert [connection] = OAuth.list_connections(user)
      assert connection.client_id == client.client_id
      assert connection.client_name == "Test Client"
      assert connection.scopes == ["mcp:read", "mcp:write"]

      assert OAuth.revoke_tokens(user.id, client.client_id) == 2
      assert OAuth.list_connections(user) == []
      assert {:error, :revoked} = ApiTokens.verify(tokens.access_token, @resource)
    end

    test "does not show one user's connections to another", %{user: user, client: client} do
      {verifier, challenge} = pkce()
      code = issue_code(client, user, challenge)
      {:ok, _tokens} = exchange(code, verifier, client)

      assert OAuth.list_connections(user_fixture()) == []
    end

    test "hides a client whose tokens have all expired", %{user: user, client: client} do
      {verifier, challenge} = pkce()
      code = issue_code(client, user, challenge)
      {:ok, _tokens} = exchange(code, verifier, client)

      past = DateTime.utc_now() |> DateTime.add(-1, :day) |> DateTime.truncate(:second)
      Repo.update_all(ApiToken, set: [expires_at: past])

      assert OAuth.list_connections(user) == []
    end
  end

  describe "prune_codes/0" do
    test "removes codes long past expiry, keeps live ones", %{user: user, client: client} do
      {_verifier, challenge} = pkce()
      issue_code(client, user, challenge)
      assert OAuth.prune_codes() == 0

      expire_codes!(-2)
      assert OAuth.prune_codes() == 1
      assert Repo.aggregate(AuthorizationCode, :count, :id) == 0
    end
  end

  defp expire_codes!(days_ago \\ 0) do
    expires_at =
      DateTime.utc_now()
      |> DateTime.add(days_ago, :day)
      |> DateTime.add(-5, :minute)
      |> DateTime.truncate(:second)

    Repo.update_all(AuthorizationCode, set: [expires_at: expires_at])
  end
end
