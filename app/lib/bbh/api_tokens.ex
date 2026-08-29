defmodule Bbh.ApiTokens do
  @moduledoc """
  Bearer credentials for the MCP endpoint (`docs/adr/0009-mcp-server.md`).

  The hashing mirrors `Bbh.Accounts.UserToken`: 32 random bytes handed to the caller
  URL-safe base64-encoded, only their SHA-256 stored. Read access to the database
  therefore does not yield a usable token.

  A token never grants more than its owner has. `verify/2` returns the user, and every
  caller runs the resulting `Bbh.Accounts.Scope` through `BbhWeb.Authz` exactly like the
  admin LiveViews do — the token's `scopes` narrow that further, they never widen it.
  """
  import Ecto.Query

  alias Bbh.ApiTokens.ApiToken
  alias Bbh.Repo

  @hash_algorithm :sha256
  @rand_size 32

  # Personal access tokens are long-lived but not eternal — a forgotten credential
  # stops working within the year rather than outliving the person who made it.
  @pat_validity_in_days 365

  @doc """
  Mints a personal access token for `user`.

  Returns `{:ok, plaintext_token, %ApiToken{}}`. The plaintext exists only in this
  return value; show it to the user once and never store it.
  """
  def create_pat(user, name, scopes) do
    expires_at =
      DateTime.utc_now()
      |> DateTime.add(@pat_validity_in_days, :day)
      |> DateTime.truncate(:second)

    mint(user, "pat", name: name, scopes: scopes, expires_at: expires_at)
  end

  @doc """
  Mints a token of `kind` for `user`.

  Options: `:name`, `:scopes`, `:resource` (the RFC 8707 audience), `:oauth_client_id`,
  `:expires_at`. Used directly by the OAuth token endpoint.
  """
  def mint(user, kind, opts \\ []) do
    token = :crypto.strong_rand_bytes(@rand_size)

    attrs = %{
      token_hash: hash(token),
      kind: kind,
      user_id: user.id,
      name: opts[:name],
      scopes: opts[:scopes] || [],
      resource: opts[:resource],
      oauth_client_id: opts[:oauth_client_id],
      expires_at: opts[:expires_at]
    }

    case %ApiToken{} |> ApiToken.changeset(attrs) |> Repo.insert() do
      {:ok, api_token} -> {:ok, encode(token), api_token}
      {:error, changeset} -> {:error, changeset}
    end
  end

  @doc """
  Resolves a plaintext bearer token to its owner.

  `resource` is the canonical URI the request was made against. A token minted for a
  different audience is rejected (RFC 8707 / the MCP requirement that servers only accept
  tokens issued for themselves). Personal access tokens carry no audience and are
  accepted at any resource of this app.

  Returns `{:ok, user, api_token}` or `{:error, :invalid | :expired | :revoked |
  :wrong_audience}`. The error reason is for logging — callers answer every case with the
  same `401`, so a probing client learns nothing from it.
  """
  def verify(token_string, resource) when is_binary(token_string) do
    with {:ok, raw} <- decode(token_string),
         %ApiToken{} = api_token <- Repo.one(by_hash_query(hash(raw))) do
      cond do
        api_token.revoked_at -> {:error, :revoked}
        not ApiToken.active?(api_token) -> {:error, :expired}
        not audience_ok?(api_token, resource) -> {:error, :wrong_audience}
        true -> {:ok, api_token.user, api_token}
      end
    else
      _ -> {:error, :invalid}
    end
  end

  def verify(_token_string, _resource), do: {:error, :invalid}

  # A PAT is not bound to an audience; an OAuth token must match exactly.
  defp audience_ok?(%ApiToken{resource: nil}, _resource), do: true
  defp audience_ok?(%ApiToken{resource: bound}, resource), do: bound == resource

  defp by_hash_query(hash) do
    from t in ApiToken, where: t.token_hash == ^hash, preload: [:user]
  end

  @doc """
  Records that a token was just used.

  Best-effort and deliberately un-awaited by correctness: a failed write costs an
  inaccurate "last used" column, never a rejected request.
  """
  def touch(%ApiToken{} = api_token) do
    now = DateTime.utc_now() |> DateTime.truncate(:second)
    Repo.update_all(from(t in ApiToken, where: t.id == ^api_token.id), set: [last_used_at: now])
    :ok
  end

  @doc "A user's personal access tokens, newest first. Revoked ones are omitted."
  def list_pats(user) do
    Repo.all(
      from t in ApiToken,
        where: t.user_id == ^user.id and t.kind == "pat" and is_nil(t.revoked_at),
        order_by: [desc: t.inserted_at]
    )
  end

  @doc """
  One of the user's own tokens, or `nil`.

  Scoped by user, so an id cannot be used to reach across accounts. A malformed UUID is a
  miss rather than a raise — cast up front, the same way `Bbh.Content.get_article/1` and
  `Bbh.Media.get_upload/1` handle ids that arrive from a client payload.
  """
  def get_for_user(user, id) do
    case Ecto.UUID.cast(id) do
      {:ok, uuid} -> Repo.one(from t in ApiToken, where: t.id == ^uuid and t.user_id == ^user.id)
      :error -> nil
    end
  end

  @doc "Revokes a token. Idempotent — re-revoking is a no-op, not an error."
  def revoke(%ApiToken{} = api_token) do
    now = DateTime.utc_now() |> DateTime.truncate(:second)

    api_token
    |> Ecto.Changeset.change(revoked_at: api_token.revoked_at || now)
    |> Repo.update()
  end

  @doc """
  Deletes tokens that expired or were revoked more than `days` ago.

  Revoked rows are kept for a grace period so `last_used_at` stays inspectable after an
  incident; expired ones carry no such value once they stop working.
  """
  def prune(days \\ 30) do
    cutoff = DateTime.utc_now() |> DateTime.add(-days, :day)

    {count, _} =
      Repo.delete_all(
        from t in ApiToken,
          where: (not is_nil(t.expires_at) and t.expires_at < ^cutoff) or t.revoked_at < ^cutoff
      )

    count
  end

  defp hash(raw), do: :crypto.hash(@hash_algorithm, raw)
  defp encode(raw), do: Base.url_encode64(raw, padding: false)

  defp decode(token_string) do
    case Base.url_decode64(token_string, padding: false) do
      {:ok, raw} -> {:ok, raw}
      :error -> :error
    end
  end
end
