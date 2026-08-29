defmodule BbhWeb.Api.OAuthController do
  @moduledoc """
  The machine-facing half of the authorization server: discovery, dynamic registration and
  the token endpoint. The half a human sees — consent — is `BbhWeb.OAuthController`.

  All of it is unauthenticated by construction. Discovery has to be readable before a
  client has any credential, registration is what *creates* the credential, and the token
  endpoint authenticates by PKCE rather than by a client secret (every client here is
  public). Rate limiting is therefore the only thing standing in front of these, and it is
  applied per IP on both write endpoints.
  """
  use BbhWeb, :controller

  alias Bbh.ApiTokens.ApiToken
  alias Bbh.OAuth
  alias BbhWeb.MCP
  alias BbhWeb.RateLimit

  require Logger

  ## Discovery

  @doc """
  RFC 9728 protected-resource metadata: what this resource is and who authorizes for it.

  Routed at both `/.well-known/oauth-protected-resource` and
  `/.well-known/oauth-protected-resource/mcp`. The spec builds the second by inserting the
  resource's path, and clients probe them in different orders; serving both costs one route
  and removes a whole class of "the connector just fails" reports.
  """
  def protected_resource(conn, _params) do
    json(conn, %{
      resource: MCP.resource_uri(),
      authorization_servers: [MCP.issuer()],
      scopes_supported: ApiToken.scopes(),
      bearer_methods_supported: ["header"]
    })
  end

  @doc """
  RFC 8414 authorization-server metadata.

  Only `oauth-authorization-server` is served, not an OpenID Connect discovery document:
  the spec requires one of the two, and a half-populated OIDC document (no `jwks_uri`, no
  id tokens) would invite a client to negotiate a protocol this server does not speak.
  """
  def authorization_server(conn, _params) do
    json(conn, %{
      issuer: MCP.issuer(),
      authorization_endpoint: url(~p"/oauth/authorize"),
      token_endpoint: url(~p"/oauth/token"),
      registration_endpoint: url(~p"/oauth/register"),
      scopes_supported: ApiToken.scopes(),
      response_types_supported: ["code"],
      response_modes_supported: ["query"],
      grant_types_supported: ["authorization_code", "refresh_token"],
      # Public clients only — PKCE is the client authentication.
      token_endpoint_auth_methods_supported: ["none"],
      code_challenge_methods_supported: ["S256"],
      # We do send `iss` on the authorization response (RFC 9207), and must say so or a
      # conforming client is entitled to ignore it.
      authorization_response_iss_parameter_supported: true
    })
  end

  ## Dynamic client registration (RFC 7591)

  def register(conn, params) do
    with :ok <- rate_limit(conn, "oauth_register", 10) do
      case OAuth.register_client(params) do
        {:ok, client} ->
          Logger.info("OAuth client registered: #{client.client_id} (#{client.client_name})")

          conn
          |> put_status(:created)
          |> json(%{
            client_id: client.client_id,
            client_id_issued_at: DateTime.to_unix(client.inserted_at),
            client_name: client.client_name,
            redirect_uris: client.redirect_uris,
            grant_types: client.grant_types,
            response_types: ["code"],
            token_endpoint_auth_method: "none",
            scope: Enum.join(client.scopes, " ")
          })

        {:error, changeset} ->
          # RFC 7591 names this error for a rejected redirect URI specifically, which is
          # the only rejection a well-formed client can realistically hit.
          error(conn, :bad_request, "invalid_redirect_uri", BbhWeb.MCP.Args.errors(changeset))
      end
    end
  end

  ## Token endpoint

  def token(conn, %{"grant_type" => "authorization_code"} = params) do
    with :ok <- rate_limit(conn, "oauth_token", 60) do
      OAuth.exchange_code(
        code: params["code"],
        client_id: params["client_id"],
        redirect_uri: params["redirect_uri"],
        code_verifier: params["code_verifier"],
        resource: params["resource"]
      )
      |> respond(conn)
    end
  end

  def token(conn, %{"grant_type" => "refresh_token"} = params) do
    with :ok <- rate_limit(conn, "oauth_token", 60) do
      OAuth.refresh(
        refresh_token: params["refresh_token"],
        client_id: params["client_id"],
        resource: params["resource"]
      )
      |> respond(conn)
    end
  end

  def token(conn, %{"grant_type" => grant}) do
    error(conn, :bad_request, "unsupported_grant_type", "This server does not issue #{grant}.")
  end

  def token(conn, _params) do
    error(conn, :bad_request, "invalid_request", ~s(A "grant_type" is required.))
  end

  defp respond({:ok, tokens}, conn) do
    conn
    # A token response must never be cached — it is a bearer credential in a response body.
    |> put_resp_header("cache-control", "no-store")
    |> put_resp_header("pragma", "no-cache")
    |> json(tokens)
  end

  defp respond({:error, :invalid_target}, conn) do
    error(conn, :bad_request, "invalid_target", "The requested resource is not this server.")
  end

  defp respond({:error, :server_error}, conn) do
    error(conn, :internal_server_error, "server_error", "Could not issue a token.")
  end

  # Everything else answers alike. A client that guesses wrong must not learn which of the
  # code, the client id, the redirect URI or the verifier was the part that failed.
  defp respond({:error, _reason}, conn) do
    error(conn, :bad_request, "invalid_grant", "The grant is invalid, expired or already used.")
  end

  ## Helpers

  defp rate_limit(conn, action, limit) do
    case RateLimit.check(action, RateLimit.client_ip(conn), limit, :timer.minutes(1)) do
      :ok ->
        :ok

      {:error, retry_after_ms} ->
        conn
        |> put_resp_header("retry-after", to_string(div(retry_after_ms, 1000) + 1))
        |> error(:too_many_requests, "temporarily_unavailable", "Too many requests.")
    end
  end

  defp error(conn, status, code, description) do
    conn
    |> put_status(status)
    |> json(%{error: code, error_description: description})
  end
end
