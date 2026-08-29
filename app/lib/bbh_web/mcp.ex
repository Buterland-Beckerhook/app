defmodule BbhWeb.MCP do
  @moduledoc """
  Shared constants for the MCP server (`docs/adr/0009-mcp-server.md`).

  The canonical resource URI is the identity this server is known by: OAuth access tokens
  are minted for it and `Bbh.ApiTokens.verify/2` rejects a token bound to anything else.
  It is derived from the endpoint at runtime rather than configured separately, so it can
  never drift from the URL clients actually reach.
  """

  @doc "Protocol revisions this server speaks, newest first."
  def supported_versions, do: ["2025-11-25", "2025-06-18"]

  @doc "The revision used when a client does not name one."
  def preferred_version, do: hd(supported_versions())

  @doc "Canonical URI of the MCP endpoint — the OAuth audience (RFC 8707)."
  def resource_uri, do: BbhWeb.Endpoint.url() <> "/mcp"

  @doc "OAuth issuer identifier: this app, without a path."
  def issuer, do: BbhWeb.Endpoint.url()

  @doc "Where clients discover how to authorize (RFC 9728)."
  def resource_metadata_url,
    do: BbhWeb.Endpoint.url() <> "/.well-known/oauth-protected-resource/mcp"

  @doc """
  The `WWW-Authenticate` challenge sent with a `401`.

  The `resource_metadata` pointer is what lets an unauthenticated client discover the
  authorization server and start the OAuth flow on its own.
  """
  def challenge(params \\ []) do
    ([~s(resource_metadata="#{resource_metadata_url()}"), ~s(scope="mcp:read mcp:write")] ++
       Enum.map(params, fn {k, v} -> ~s(#{k}="#{v}") end))
    |> Enum.join(", ")
    |> then(&("Bearer " <> &1))
  end
end
