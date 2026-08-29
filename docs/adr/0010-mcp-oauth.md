# ADR 0010 — The app is its own OAuth authorization server, and the site login is the OAuth login

**Status:** Accepted (2026-08-29)

## Context

[ADR 0009](0009-mcp-server.md) left the MCP endpoint reachable only by clients that can
send a custom header. Claude Code can. The Claude app — the client that matters for the
scenario the whole thing exists for, an editor writing an article from their phone at an
event — cannot: its connector dialog offers a server URL and nothing else, and it
discovers how to authenticate by walking RFC 9728 → RFC 8414 → dynamic registration →
authorization code with PKCE. A personal access token has no way in.

So either the endpoint stays desk-bound, or this app becomes an OAuth 2.1 authorization
server. There is no third option: the specification does not admit a "just paste a token"
path for that client, and running a separate identity provider for one small club website
would be a second system to secure, back up and keep alive on a host that already has
little to spare.

## Decision

**This app is the authorization server for its own MCP endpoint**, implementing exactly
the profile the MCP specification requires and nothing beyond it: RFC 7591 dynamic
registration, authorization code with PKCE `S256`, RFC 8707 resource indicators, RFC 9207
`iss` on the authorization response, and rotating refresh tokens. `Bbh.OAuth` is roughly
350 lines; the token storage is the `api_tokens` table ADR 0009 already designed for two
kinds of credential, so this stage added no migration to it.

### The user's own login is the OAuth login

`GET /oauth/authorize` runs on the browser pipeline behind `require_authenticated_user`.
An unauthenticated visitor lands in the ordinary site login — magic link or passkey, plus
TOTP where enabled — and returns to consent afterwards.

This is the decision that keeps the surface small. A dedicated OAuth login form would be a
second credential path to the same accounts, with its own rate limiting, its own
brute-force behaviour and its own way to get 2FA wrong. There is one door, and OAuth
queues at it like everything else.

### Public clients only, and the redirect URI is the boundary

Registration is open and unauthenticated, because that is what dynamic registration is. A
client secret issued to anyone who asks protects nothing, so there are none: PKCE is what
binds an authorization code to the client that requested it.

That makes the registered redirect URIs the security boundary, and they are validated as
such. HTTPS anywhere; plaintext HTTP only for loopback, which never leaves the machine and
is how every native client receives its callback. Fragments are rejected rather than
ignored — they are never sent to the server, so they can only hide something. Matching at
redemption is exact string comparison, with no normalization and no prefix rule: "close
enough" is precisely what turns an open registration endpoint into an account-takeover
primitive.

### Everything the token request must prove is frozen at consent time

The client, the exact redirect URI, the PKCE challenge, the audience and the scopes are
written onto the authorization code row when the user approves. Redemption compares
against what the user consented to, never against what the client re-sends. The consent
POST re-validates every parameter from scratch for the same reason — its values arrive as
hidden form fields, so trusting them because they came from our own markup would let a
crafted form swap the redirect URI after the user has read the original one.

### Replay takes the family down

An authorization code may be spent once, and spending it is a conditional `UPDATE` so two
simultaneous redemptions cannot both win. A second redemption means the code leaked or the
client is broken; both revoke every token that client holds for that user.

Refresh tokens rotate: the presented token is revoked whether or not the client ever uses
the new one, so a refresh token that shows up after rotation is a copy. It also revokes
the whole family. After a replay we cannot tell the thief from the client, and the
recoverable outcome — the real client walks through consent again — is much better than
the alternative.

### Errors say as little as possible, except where they must say more

Every token-endpoint failure that is not an audience mismatch answers with the same
`invalid_grant` body. A client guessing must not learn which of the code, the client id,
the redirect URI or the verifier was the part that failed.

The authorize endpoint splits the other way, and that split is a security rule rather than
a style choice. An unusable `client_id` or an unregistered `redirect_uri` renders an error
page here, because redirecting to an unvalidated URI is the open redirect this protocol
exists to prevent. Every later failure redirects back to the client, where the client can
act on it.

## Consequences

- Anyone can register a client. That is by design and the reason registration is
  rate-limited per IP; a registration on its own grants nothing until a logged-in user
  reads a consent screen and approves it. `Bbh.OAuth.Client` caps the registry at five
  redirect URIs of 2000 bytes so it cannot be used as storage.
- Access tokens live an hour, refresh tokens 30 days, codes 60 seconds. A connection that
  goes unused for a month asks for consent again.
- Tokens are bound to the canonical MCP URI (RFC 8707), which is derived from the endpoint
  at runtime rather than configured, so it cannot drift from the URL clients actually
  reach. `Bbh.ApiTokens.verify/2` refuses a token minted for anything else. The one caller
  allowed to skip that check is the token endpoint on a refresh, where the audience is a
  property of the grant rather than of the request.
- `/admin/einstellungen` (Tab „Token") lists connected apps beside personal access tokens
  and disconnects one on a click. The list is derived from live `api_tokens` rather than a
  separate grant table, so it cannot claim a connection that no longer works.
- No `client_credentials`, no OpenID Connect discovery document, no id tokens, no `plain`
  PKCE. A half-populated OIDC document would invite a client to negotiate a protocol this
  server does not speak, and `plain` puts the verifier in the authorization request, which
  is the thing PKCE exists to keep out of it.
- Codes outlive their minute of validity by a day before `Bbh.Workers.AuthPruner` sweeps
  them, so a replay still finds the row and can trigger the revocation above.
