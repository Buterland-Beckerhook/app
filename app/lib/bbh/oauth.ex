defmodule Bbh.OAuth do
  @moduledoc """
  The OAuth 2.1 authorization server in front of `/mcp` (`docs/adr/0010-mcp-oauth.md`).

  It exists for one reason: the Claude app's connector dialog offers OAuth fields and
  nothing else, so a personal access token — which Claude Code accepts as a header —
  cannot connect it. The whole surface here is the minimum that makes that dialog work:
  open registration, an authorization code with PKCE, and a rotating refresh token.

  Two properties are load-bearing and worth stating up front.

  **The user's own login is the OAuth login.** `/oauth/authorize` runs on the browser
  pipeline behind `require_authenticated_user`, so magic link, passkey and TOTP all apply
  unchanged. There is no second credential path to keep secure.

  **Everything the token request must prove is frozen at consent time.** The client, the
  exact redirect URI, the PKCE challenge, the audience and the scopes are written onto the
  authorization code; redemption compares against what the user approved, never against
  what the client re-sends.
  """
  import Ecto.Query

  alias Bbh.ApiTokens
  alias Bbh.ApiTokens.ApiToken
  alias Bbh.OAuth.AuthorizationCode
  alias Bbh.OAuth.Client
  alias Bbh.Repo

  require Logger

  @hash_algorithm :sha256
  @rand_size 32

  # Long enough to survive a slow redirect chain, short enough that a code sitting in a
  # browser history or a proxy log is worthless by the time anyone reads it.
  @code_validity_in_seconds 60
  @access_validity_in_seconds 3600
  @refresh_validity_in_days 30

  @doc "Seconds an access token stays valid — the `expires_in` of a token response."
  def access_validity_in_seconds, do: @access_validity_in_seconds

  ## Client registration

  @doc """
  Registers a client from an RFC 7591 request body.

  The endpoint is unauthenticated by design — that is what dynamic registration is — so
  this accepts only the fields it understands and ignores the rest of the metadata a
  client may send. The `client_id` is generated here; a value supplied by the caller is
  never honoured.
  """
  def register_client(attrs) when is_map(attrs) do
    %Client{}
    |> Client.changeset(%{
      client_id: generate_client_id(),
      client_name: attrs["client_name"],
      redirect_uris: attrs["redirect_uris"],
      grant_types: normalize_grant_types(attrs["grant_types"]),
      scopes: requested_scopes(attrs["scope"])
    })
    |> Repo.insert()
  end

  defp generate_client_id, do: "bbh-" <> Base.url_encode64(random_bytes(), padding: false)

  # Absent means the RFC 7591 default, which is authorization_code alone; we always allow
  # refresh_token alongside it because an MCP client that cannot refresh would send the
  # user back through consent every hour.
  defp normalize_grant_types(nil), do: Client.grant_types()

  defp normalize_grant_types(types) when is_list(types),
    do: Enum.filter(types, &(&1 in Client.grant_types()))

  defp normalize_grant_types(_types), do: Client.grant_types()

  @doc "A registered client by its public `client_id`, or `nil`."
  def get_client(client_id) when is_binary(client_id),
    do: Repo.get_by(Client, client_id: client_id)

  def get_client(_client_id), do: nil

  @doc """
  Parses a space-delimited `scope` string into the scopes this server grants.

  Unknown scopes are dropped rather than rejected: a client asking for something we do not
  have should get a working connection with less, which is what `scopes_supported` in the
  metadata told it to expect.
  """
  def requested_scopes(nil), do: ApiToken.scopes()

  def requested_scopes(scope) when is_binary(scope) do
    case scope |> String.split(~r/\s+/, trim: true) |> Enum.filter(&(&1 in ApiToken.scopes())) do
      [] -> ApiToken.scopes()
      scopes -> scopes
    end
  end

  def requested_scopes(_scope), do: ApiToken.scopes()

  ## Authorization code

  @doc """
  Issues an authorization code for `user`, recording what they consented to.

  The caller must already have validated the client, the redirect URI and the resource —
  by the time this runs the only question left is which user approved what.
  """
  def create_authorization_code(%Client{} = client, user, params) do
    code = random_bytes()

    expires_at =
      DateTime.utc_now()
      |> DateTime.add(@code_validity_in_seconds, :second)
      |> DateTime.truncate(:second)

    attrs = %{
      code_hash: hash(code),
      client_id: client.client_id,
      user_id: user.id,
      redirect_uri: params.redirect_uri,
      code_challenge: params.code_challenge,
      resource: params.resource,
      scopes: params.scopes,
      expires_at: expires_at
    }

    case %AuthorizationCode{} |> AuthorizationCode.changeset(attrs) |> Repo.insert() do
      {:ok, _record} -> {:ok, encode(code)}
      {:error, changeset} -> {:error, changeset}
    end
  end

  ## Token endpoint

  @doc """
  Redeems an authorization code for an access/refresh token pair.

  Every check that follows is a way for this to fail closed: the code must exist, be
  unspent, be unexpired, belong to this client, name this redirect URI, be for this
  audience, and be unlocked by a verifier that hashes to the stored challenge.

  Replaying a spent code revokes every token that client holds for that user. A second
  redemption means either the code leaked or the client is broken, and neither is a state
  in which its existing tokens should keep working.
  """
  def exchange_code(params) do
    with {:ok, code} <- fetch_code(params[:code]),
         :ok <- check_replay(code),
         :ok <- check_binding(code, params),
         :ok <- verify_pkce(code, params[:code_verifier]),
         {:ok, code} <- mark_used(code) do
      user = Repo.get!(Bbh.Accounts.User, code.user_id)
      issue_tokens(user, code.client_id, code.scopes, code.resource)
    end
  end

  defp fetch_code(code_string) when is_binary(code_string) do
    with {:ok, raw} <- decode(code_string),
         %AuthorizationCode{} = code <- Repo.get_by(AuthorizationCode, code_hash: hash(raw)) do
      {:ok, code}
    else
      _ -> {:error, :invalid_grant}
    end
  end

  defp fetch_code(_code_string), do: {:error, :invalid_grant}

  defp check_replay(%AuthorizationCode{used_at: nil} = code) do
    if AuthorizationCode.redeemable?(code), do: :ok, else: {:error, :invalid_grant}
  end

  defp check_replay(%AuthorizationCode{} = code) do
    Logger.warning("OAuth authorization code replayed for client #{code.client_id}")
    revoke_tokens(code.user_id, code.client_id)
    {:error, :invalid_grant}
  end

  # The client, redirect URI and audience must be the ones the user consented to. A client
  # that sends different values is not the client the code was issued for.
  defp check_binding(code, params) do
    cond do
      code.client_id != params[:client_id] -> {:error, :invalid_grant}
      code.redirect_uri != params[:redirect_uri] -> {:error, :invalid_grant}
      not audience_matches?(code.resource, params[:resource]) -> {:error, :invalid_target}
      true -> :ok
    end
  end

  # A token request may repeat the `resource` it asked for at authorize time, or omit it
  # and inherit what the code carries. It may not change it.
  defp audience_matches?(_bound, nil), do: true
  defp audience_matches?(bound, requested), do: bound == requested

  defp verify_pkce(code, verifier) when is_binary(verifier) do
    computed = Base.url_encode64(:crypto.hash(:sha256, verifier), padding: false)

    if Plug.Crypto.secure_compare(computed, code.code_challenge),
      do: :ok,
      else: {:error, :invalid_grant}
  end

  defp verify_pkce(_code, _verifier), do: {:error, :invalid_grant}

  # Spending the code is a conditional update, so two simultaneous redemptions cannot both
  # win: whichever loses the race sees zero rows updated and is refused.
  defp mark_used(code) do
    now = DateTime.utc_now() |> DateTime.truncate(:second)

    query =
      from c in AuthorizationCode, where: c.id == ^code.id and is_nil(c.used_at)

    case Repo.update_all(query, set: [used_at: now]) do
      {1, _} -> {:ok, code}
      {0, _} -> {:error, :invalid_grant}
    end
  end

  @doc """
  Exchanges a refresh token for a new pair, rotating it.

  The presented token is revoked whether or not the client ever uses the new one. A
  refresh token that is presented after rotation is therefore a stolen copy, and it takes
  the whole family down with it — `revoke_tokens/2` on the same client and user.

  The audience is checked against the *token*, not against the request: `resource` is
  optional on a refresh, and a client that omits it must keep the audience it was granted
  rather than be refused for not repeating itself.
  """
  def refresh(params) do
    case ApiTokens.verify(params[:refresh_token] || "", :any) do
      {:ok, user, %ApiToken{kind: "refresh"} = token} ->
        cond do
          token.oauth_client_id != params[:client_id] ->
            {:error, :invalid_grant}

          not audience_matches?(token.resource, params[:resource]) ->
            {:error, :invalid_target}

          true ->
            {:ok, _} = ApiTokens.revoke(token)
            issue_tokens(user, token.oauth_client_id, token.scopes, token.resource)
        end

      {:ok, _user, _other_kind} ->
        # An access token or a PAT is not a refresh token, however valid it is.
        {:error, :invalid_grant}

      {:error, :revoked} ->
        replayed_refresh_token(params)

      {:error, _reason} ->
        {:error, :invalid_grant}
    end
  end

  # Already-revoked means either a rotated token being replayed or a token the user killed
  # by hand. Both warrant taking down the rest of the family; the lookup is by hash, so it
  # only finds the exact token presented.
  defp replayed_refresh_token(params) do
    with {:ok, raw} <- decode(params[:refresh_token] || ""),
         %ApiToken{} = token <- Repo.get_by(ApiToken, token_hash: hash(raw)) do
      Logger.warning("Revoked OAuth refresh token replayed for client #{token.oauth_client_id}")
      revoke_tokens(token.user_id, token.oauth_client_id)
    end

    {:error, :invalid_grant}
  end

  defp issue_tokens(user, client_id, scopes, resource) do
    now = DateTime.utc_now()

    with {:ok, access, _} <-
           ApiTokens.mint(user, "access",
             scopes: scopes,
             resource: resource,
             oauth_client_id: client_id,
             expires_at: DateTime.add(now, @access_validity_in_seconds, :second) |> trunc_s()
           ),
         {:ok, refresh, _} <-
           ApiTokens.mint(user, "refresh",
             scopes: scopes,
             resource: resource,
             oauth_client_id: client_id,
             expires_at: DateTime.add(now, @refresh_validity_in_days, :day) |> trunc_s()
           ) do
      {:ok,
       %{
         access_token: access,
         token_type: "Bearer",
         expires_in: @access_validity_in_seconds,
         refresh_token: refresh,
         scope: Enum.join(scopes, " ")
       }}
    else
      {:error, _changeset} -> {:error, :server_error}
    end
  end

  defp trunc_s(datetime), do: DateTime.truncate(datetime, :second)

  ## Connected apps

  @doc """
  The clients that currently hold live tokens for `user`, newest connection first.

  Driven off `api_tokens` rather than a separate grant table: a connection *is* its live
  tokens, so this cannot drift out of sync with what actually works.
  """
  def list_connections(user) do
    tokens =
      Repo.all(
        from t in ApiToken,
          where:
            t.user_id == ^user.id and not is_nil(t.oauth_client_id) and is_nil(t.revoked_at) and
              t.expires_at > ^DateTime.utc_now(),
          order_by: [desc: t.inserted_at]
      )

    names =
      tokens
      |> Enum.map(& &1.oauth_client_id)
      |> Enum.uniq()
      |> then(&Repo.all(from c in Client, where: c.client_id in ^&1))
      |> Map.new(&{&1.client_id, &1.client_name})

    tokens
    |> Enum.group_by(& &1.oauth_client_id)
    |> Enum.map(fn {client_id, group} ->
      %{
        client_id: client_id,
        client_name: Map.get(names, client_id) || client_id,
        scopes: group |> Enum.flat_map(& &1.scopes) |> Enum.uniq(),
        connected_at: group |> Enum.map(& &1.inserted_at) |> Enum.min(DateTime),
        last_used_at:
          group |> Enum.map(& &1.last_used_at) |> Enum.reject(&is_nil/1) |> max_or_nil()
      }
    end)
    |> Enum.sort_by(& &1.connected_at, {:desc, DateTime})
  end

  defp max_or_nil([]), do: nil
  defp max_or_nil(dates), do: Enum.max(dates, DateTime)

  @doc ~S(Revokes every token a client holds for a user — what "disconnect" means.)
  def revoke_tokens(user_id, client_id) when is_binary(client_id) do
    now = DateTime.utc_now() |> DateTime.truncate(:second)

    {count, _} =
      Repo.update_all(
        from(t in ApiToken,
          where:
            t.user_id == ^user_id and t.oauth_client_id == ^client_id and is_nil(t.revoked_at)
        ),
        set: [revoked_at: now]
      )

    count
  end

  def revoke_tokens(_user_id, _client_id), do: 0

  @doc """
  Deletes authorization codes a day past their minute of validity.

  The day is not caution about clocks: a spent code has to outlive itself long enough for
  a replay to still find the row and trigger `revoke_tokens/2`. After that the row is
  worthless — unlike a revoked token, it records nothing anyone would want to inspect.
  """
  def prune_codes do
    cutoff = DateTime.utc_now() |> DateTime.add(-1, :day)

    {count, _} =
      Repo.delete_all(from c in AuthorizationCode, where: c.expires_at < ^cutoff)

    count
  end

  ## Credential helpers — same construction as Bbh.ApiTokens

  defp random_bytes, do: :crypto.strong_rand_bytes(@rand_size)
  defp hash(raw), do: :crypto.hash(@hash_algorithm, raw)
  defp encode(raw), do: Base.url_encode64(raw, padding: false)

  defp decode(value) when is_binary(value), do: Base.url_decode64(value, padding: false)
  defp decode(_value), do: :error
end
