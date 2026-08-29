defmodule BbhWeb.OAuthController do
  @moduledoc """
  The consent screen: the one part of the OAuth flow a person sees.

  Runs on the browser pipeline behind `require_authenticated_user`, so an unauthenticated
  visitor is sent through the app's ordinary login — magic link or passkey, plus TOTP —
  and returns here afterwards (`maybe_store_return_to/1` keeps the full query string).
  That is deliberate: the site's login *is* the OAuth login, and there is no second
  credential path to keep secure.

  Both actions re-validate every parameter from scratch. `GET` renders the screen and
  `POST` issues the code, but the POST's values arrive as hidden form fields — i.e. from
  the client — so trusting them because they "came from our own form" would let a crafted
  form swap the redirect URI after the user read the original one.

  Error handling follows OAuth's split, which is a security rule rather than a style
  choice: an unusable `client_id` or an unregistered `redirect_uri` is shown on our own
  page, because redirecting to an unvalidated URI is exactly the open-redirect this
  protocol has to avoid. Anything else redirects back to the client as an error.
  """
  use BbhWeb, :controller

  alias Bbh.OAuth
  alias BbhWeb.MCP

  require Logger

  def new(conn, params) do
    case validate(params) do
      {:ok, ctx} ->
        render(conn, :new,
          client: ctx.client,
          scopes: ctx.scopes,
          params: passthrough(params)
        )

      {:fatal, message} ->
        render_fatal(conn, message)

      {:redirect, code, description} ->
        redirect_error(conn, params, code, description)
    end
  end

  def create(conn, %{"decision" => decision} = params) do
    case validate(params) do
      {:ok, ctx} ->
        if decision == "approve",
          do: approve(conn, ctx, params),
          else: redirect_error(conn, params, "access_denied", "Die Freigabe wurde abgelehnt.")

      {:fatal, message} ->
        render_fatal(conn, message)

      {:redirect, code, description} ->
        redirect_error(conn, params, code, description)
    end
  end

  def create(conn, params),
    do: redirect_error(conn, params, "invalid_request", "Missing decision.")

  defp approve(conn, ctx, params) do
    user = conn.assigns.current_scope.user

    case OAuth.create_authorization_code(ctx.client, user, ctx) do
      {:ok, code} ->
        Logger.info("OAuth consent granted to #{ctx.client.client_id} by #{user.email}")

        redirect(conn,
          external: build_redirect(ctx.redirect_uri, %{"code" => code}, params["state"])
        )

      {:error, _changeset} ->
        redirect_error(conn, params, "server_error", "Der Code konnte nicht erstellt werden.")
    end
  end

  ## Validation

  # Ordered so that the two checks which forbid redirecting run first. Until both the
  # client and the redirect URI are known-good there is nowhere safe to send the browser,
  # so those failures render here; everything after them is reported to the client.
  defp validate(params) do
    with {:ok, client} <- fetch_client(params["client_id"]),
         {:ok, redirect_uri} <- fetch_redirect_uri(client, params["redirect_uri"]),
         :ok <- check_response_type(params["response_type"]),
         {:ok, challenge} <- fetch_pkce(params),
         :ok <- check_resource(params["resource"]) do
      {:ok,
       %{
         client: client,
         redirect_uri: redirect_uri,
         code_challenge: challenge,
         resource: MCP.resource_uri(),
         scopes: OAuth.requested_scopes(params["scope"])
       }}
    end
  end

  defp fetch_client(client_id) do
    case OAuth.get_client(client_id) do
      nil -> {:fatal, "Diese Anwendung ist hier nicht registriert."}
      client -> {:ok, client}
    end
  end

  defp fetch_redirect_uri(client, redirect_uri) do
    if OAuth.Client.registered_redirect_uri?(client, redirect_uri) do
      {:ok, redirect_uri}
    else
      {:fatal, "Die Rücksprungadresse gehört nicht zu dieser Anwendung."}
    end
  end

  defp check_response_type("code"), do: :ok

  defp check_response_type(_other),
    do: {:redirect, "unsupported_response_type", "Only response_type=code is supported."}

  # S256 only. `plain` is still in the RFC and is worthless — it puts the verifier in the
  # authorization request, which is the thing PKCE exists to keep out of it.
  defp fetch_pkce(%{"code_challenge" => challenge, "code_challenge_method" => "S256"})
       when is_binary(challenge) and challenge != "",
       do: {:ok, challenge}

  defp fetch_pkce(%{"code_challenge_method" => method}) when method != "S256",
    do: {:redirect, "invalid_request", "Only code_challenge_method=S256 is supported."}

  defp fetch_pkce(_params),
    do: {:redirect, "invalid_request", "A PKCE code_challenge with S256 is required."}

  # RFC 8707: the token must be minted for this server and no other. Accepting a missing
  # `resource` keeps older clients working; accepting a *different* one would let this
  # server issue tokens addressed elsewhere.
  defp check_resource(nil), do: :ok

  defp check_resource(resource) do
    if resource == MCP.resource_uri(),
      do: :ok,
      else:
        {:redirect, "invalid_target",
         "This authorization server only issues tokens for #{MCP.resource_uri()}."}
  end

  ## Responses

  defp render_fatal(conn, message) do
    conn
    |> put_status(:bad_request)
    |> render(:error, message: message)
  end

  defp redirect_error(conn, params, code, description) do
    # Only reachable once the redirect URI has been validated against the registration —
    # `validate/1` orders its checks to guarantee that.
    case OAuth.get_client(params["client_id"]) do
      nil ->
        render_fatal(conn, "Diese Anwendung ist hier nicht registriert.")

      client ->
        if OAuth.Client.registered_redirect_uri?(client, params["redirect_uri"]) do
          query = %{"error" => code, "error_description" => description}
          redirect(conn, external: build_redirect(params["redirect_uri"], query, params["state"]))
        else
          render_fatal(conn, "Die Rücksprungadresse gehört nicht zu dieser Anwendung.")
        end
    end
  end

  # `iss` on every response, success and error alike (RFC 9207) — it is what lets a client
  # talking to several authorization servers tell which one answered, and the metadata
  # advertises that we send it.
  defp build_redirect(redirect_uri, query, state) do
    query =
      query
      |> Map.put("iss", MCP.issuer())
      |> maybe_put_state(state)

    uri = URI.parse(redirect_uri)
    existing = URI.decode_query(uri.query || "")

    URI.to_string(%{uri | query: URI.encode_query(Map.merge(existing, query))})
  end

  defp maybe_put_state(query, state) when is_binary(state) and state != "",
    do: Map.put(query, "state", state)

  defp maybe_put_state(query, _state), do: query

  # The parameters the consent form has to hand back so the POST can re-validate them.
  # Re-validated, never trusted: this is a convenience for the round trip, not a channel.
  defp passthrough(params) do
    Map.take(params, [
      "client_id",
      "redirect_uri",
      "response_type",
      "code_challenge",
      "code_challenge_method",
      "state",
      "scope",
      "resource"
    ])
  end
end
