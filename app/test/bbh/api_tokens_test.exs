defmodule Bbh.ApiTokensTest do
  use Bbh.DataCase, async: true

  import Bbh.AccountsFixtures

  alias Bbh.ApiTokens
  alias Bbh.ApiTokens.ApiToken
  alias Bbh.Repo

  @resource "https://example.test/mcp"

  setup do
    %{user: user_fixture()}
  end

  describe "create_pat/3" do
    test "returns the plaintext once and stores only its hash", %{user: user} do
      {:ok, plaintext, token} = ApiTokens.create_pat(user, "iPhone", ["mcp:read", "mcp:write"])

      assert is_binary(plaintext)
      # The stored value must not be the token itself, nor recoverable from it.
      refute token.token_hash == plaintext

      assert token.token_hash ==
               :crypto.hash(:sha256, Base.url_decode64!(plaintext, padding: false))

      assert token.kind == "pat"
      assert token.name == "iPhone"
      assert token.scopes == ["mcp:read", "mcp:write"]
      # A PAT carries no audience, so it works against any resource of this app.
      assert is_nil(token.resource)
    end

    test "expires within the year", %{user: user} do
      {:ok, _plaintext, token} = ApiTokens.create_pat(user, "iPhone", ["mcp:read"])

      assert DateTime.after?(token.expires_at, DateTime.utc_now())
      assert DateTime.diff(token.expires_at, DateTime.utc_now(), :day) in 364..365
    end

    test "rejects an unknown scope", %{user: user} do
      assert {:error, changeset} = ApiTokens.create_pat(user, "iPhone", ["admin:everything"])
      assert %{scopes: ["enthält einen ungültigen Scope"]} = errors_on(changeset)
    end

    test "two tokens never collide", %{user: user} do
      {:ok, a, _} = ApiTokens.create_pat(user, "a", ["mcp:read"])
      {:ok, b, _} = ApiTokens.create_pat(user, "b", ["mcp:read"])
      refute a == b
    end
  end

  describe "verify/2" do
    test "resolves a valid token to its owner", %{user: user} do
      {:ok, plaintext, token} = ApiTokens.create_pat(user, "iPhone", ["mcp:read"])

      assert {:ok, found_user, found_token} = ApiTokens.verify(plaintext, @resource)
      assert found_user.id == user.id
      assert found_token.id == token.id
    end

    test "rejects an unknown, malformed or non-string token" do
      assert {:error, :invalid} = ApiTokens.verify("not-a-real-token", @resource)
      assert {:error, :invalid} = ApiTokens.verify("!!! not base64 !!!", @resource)
      assert {:error, :invalid} = ApiTokens.verify(nil, @resource)
    end

    test "rejects a revoked token", %{user: user} do
      {:ok, plaintext, token} = ApiTokens.create_pat(user, "iPhone", ["mcp:read"])
      {:ok, _} = ApiTokens.revoke(token)

      assert {:error, :revoked} = ApiTokens.verify(plaintext, @resource)
    end

    test "rejects an expired token", %{user: user} do
      {:ok, plaintext, token} = ApiTokens.create_pat(user, "iPhone", ["mcp:read"])
      expire!(token)

      assert {:error, :expired} = ApiTokens.verify(plaintext, @resource)
    end

    test "rejects a token minted for a different audience", %{user: user} do
      {:ok, plaintext, _token} =
        ApiTokens.mint(user, "access", scopes: ["mcp:read"], resource: "https://other.test/mcp")

      assert {:error, :wrong_audience} = ApiTokens.verify(plaintext, @resource)
      assert {:ok, _user, _token} = ApiTokens.verify(plaintext, "https://other.test/mcp")
    end
  end

  describe "mint/3" do
    test "records the OAuth client and audience a token was issued for", %{user: user} do
      {:ok, plaintext, token} =
        ApiTokens.mint(user, "access",
          scopes: ["mcp:read"],
          resource: @resource,
          oauth_client_id: "client-abc"
        )

      assert token.kind == "access"
      assert token.oauth_client_id == "client-abc"
      assert token.resource == @resource
      # No name: an OAuth token is identified by its client, not by a label a human typed.
      assert is_nil(token.name)
      assert {:ok, found, _} = ApiTokens.verify(plaintext, @resource)
      assert found.id == user.id
    end

    test "a token minted already expired is refused at once", %{user: user} do
      past = DateTime.utc_now() |> DateTime.add(-1, :minute) |> DateTime.truncate(:second)

      {:ok, plaintext, _token} =
        ApiTokens.mint(user, "refresh", scopes: ["mcp:write"], expires_at: past)

      assert {:error, :expired} = ApiTokens.verify(plaintext, @resource)
    end

    test "defaults to no scopes, which grants no tool", %{user: user} do
      {:ok, _plaintext, token} = ApiTokens.mint(user, "access")

      assert token.scopes == []
      assert is_nil(token.expires_at)
    end

    test "rejects an unknown kind", %{user: user} do
      assert {:error, changeset} = ApiTokens.mint(user, "sudo", scopes: ["mcp:read"])
      assert %{kind: ["is invalid"]} = errors_on(changeset)
    end
  end

  describe "revoke/1 and list_pats/1" do
    test "revoking is idempotent and keeps the original timestamp", %{user: user} do
      {:ok, _plaintext, token} = ApiTokens.create_pat(user, "iPhone", ["mcp:read"])

      {:ok, revoked} = ApiTokens.revoke(token)
      {:ok, again} = ApiTokens.revoke(revoked)

      assert revoked.revoked_at == again.revoked_at
    end

    test "listing hides revoked tokens and other users' tokens", %{user: user} do
      other = user_fixture()
      {:ok, _, keep} = ApiTokens.create_pat(user, "keep", ["mcp:read"])
      {:ok, _, drop} = ApiTokens.create_pat(user, "drop", ["mcp:read"])
      {:ok, _, _foreign} = ApiTokens.create_pat(other, "foreign", ["mcp:read"])
      {:ok, _} = ApiTokens.revoke(drop)

      assert [listed] = ApiTokens.list_pats(user)
      assert listed.id == keep.id
    end
  end

  describe "get_for_user/2" do
    test "will not reach across accounts", %{user: user} do
      other = user_fixture()
      {:ok, _plaintext, token} = ApiTokens.create_pat(other, "foreign", ["mcp:read"])

      assert is_nil(ApiTokens.get_for_user(user, token.id))
      assert ApiTokens.get_for_user(other, token.id).id == token.id
    end

    test "treats a malformed id as a miss rather than raising", %{user: user} do
      assert is_nil(ApiTokens.get_for_user(user, "not-a-uuid"))
    end
  end

  describe "touch/1" do
    test "records the last use", %{user: user} do
      {:ok, _plaintext, token} = ApiTokens.create_pat(user, "iPhone", ["mcp:read"])
      assert is_nil(token.last_used_at)

      :ok = ApiTokens.touch(token)

      assert Repo.get!(ApiToken, token.id).last_used_at
    end
  end

  describe "prune/1" do
    test "removes long-expired tokens but keeps live ones", %{user: user} do
      {:ok, _, live} = ApiTokens.create_pat(user, "live", ["mcp:read"])
      {:ok, _, stale} = ApiTokens.create_pat(user, "stale", ["mcp:read"])
      expire!(stale, -90)

      assert ApiTokens.prune(30) == 1
      assert Repo.get(ApiToken, live.id)
      refute Repo.get(ApiToken, stale.id)
    end
  end

  defp expire!(token, days_ago \\ -1) do
    expires_at = DateTime.utc_now() |> DateTime.add(days_ago, :day) |> DateTime.truncate(:second)
    token |> Ecto.Changeset.change(expires_at: expires_at) |> Repo.update!()
  end
end
