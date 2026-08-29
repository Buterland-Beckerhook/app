# ADR 0009 — The MCP server is built into the app, stateless, and cannot delete

**Status:** Accepted (2026-08-28)

## Context

Editors have exactly one way to create content: the LiveView admin at `/admin`. That
works at a desk. It does not work standing at a Schützenfest with a phone, which is
precisely when the article is worth writing — while the pictures are fresh and the names
are still in someone's head.

An AI assistant can bridge that, but only if it can reach the content contexts. The
Model Context Protocol is the interface Claude and comparable clients already speak, so
the question is not *whether* to expose one but *where it lives* and *what it may touch*.

The alternative — a generic REST API plus a separate MCP proxy — was rejected before it
was written down: it would mean a second write path around `Bbh.Content`, and the
sanitization, search reindexing and publish-notification bookkeeping would have to be
kept in sync in two places.

## Decision

**The MCP server is a route in this app** (`POST /mcp`), not a separate service. Its
tools call `Bbh.Content` and `Bbh.Media` directly, so every write crosses the same
changesets as the admin form. `Bbh.Html.sanitize/1` in particular runs on
model-authored HTML exactly where it runs on Quill-authored HTML.

### Hand-rolled, not `anubis_mcp`

`anubis_mcp` (the maintained Hermes fork) is a real option and would have supplied the
protocol. It also brings its own supervision trees and session registry for a server that
needs neither. The protocol surface we actually use — `initialize`, `ping`, `tools/list`,
`tools/call`, notifications — is about 150 lines of JSON-RPC dispatch in
`BbhWeb.MCP.Server`. Production runs on a small, swapless, shared host; a dependency that
costs supervision processes at rest to save a file we can read in one sitting is the wrong
trade here.

### Stateless: JSON responses, no SSE, no session

The Streamable HTTP transport lets a server answer a request with either
`Content-Type: text/event-stream` or a single `application/json` object, and lets it
decline to issue an `Mcp-Session-Id`. We take both outs. `GET /mcp` (open a
server-to-client stream) and `DELETE /mcp` (end a session) therefore answer `405`, which
is the transport's documented way of saying "not offered here" and which clients handle.

The consequence worth stating: the endpoint holds nothing between requests and costs
nothing at rest. Tool calls are short and synchronous, so there is nothing to stream.

Protocol revisions `2025-11-25` and `2025-06-18` are advertised. `initialize` echoes the
client's revision when we speak it; an `MCP-Protocol-Version` header naming one we do not
is a `400`, as required.

### Tokens live in their own table

`api_tokens`, not `users_tokens`. Two reasons, and the first is the one that bites:
`Accounts.update_user_and_delete_all_tokens/1` deletes *every* row a user owns whenever
their email is confirmed or changed. A token in that table would be silently destroyed by
an unrelated account action, and the integration would fail with no visible cause.
Second, `name`, `last_used_at`, `revoked_at`, `resource` and `oauth_client_id` have no
business on the session-token schema.

The hashing is copied from `Bbh.Accounts.UserToken`: 32 random bytes to the caller,
SHA-256 in the database. The table is shaped for OAuth from the start (`kind`,
`resource`, `oauth_client_id`) so adding the authorization server needs no migration
here.

### Permissions follow the user; scopes only narrow

A token is not a role. `BbhWeb.Plugs.ApiAuth` resolves it to the owning user and assigns
the very same `Bbh.Accounts.Scope` the admin LiveViews run on; `BbhWeb.MCP.Tools` then
authorizes through `BbhWeb.Authz` exactly as they do. The token's scopes (`mcp:read`,
`mcp:write`) narrow that further and can never widen it. A `calendar_editor` gets an
empty tool list, because this server exposes no calendar tools and they may not touch
content.

`tools/list` is filtered rather than merely guarded: showing a model tools that will
always fail wastes its attempts and its patience. `tools/call` re-checks anyway, since a
client may call a name it was never offered.

### Nothing deletes

No tool deletes an article, a block, a media item or a gallery entry — the operations are
simply absent, not permission-gated. Deletion is cheap to request in natural language,
expensive to undo, and easy to trigger from an ambiguous instruction; it stays a
deliberate act in `/admin` behind its type-the-slug confirmation. New articles default to
`draft` for the adjacent reason: publishing fires `Bbh.Workers.ArticlePublishNotifier` and
a web push to every subscriber within five minutes.

### CORS is permissive here, and only here

`/mcp` answers `Access-Control-Allow-Origin: *`. That would be reckless on the browser
pipeline and is safe on this one, for a specific reason: the route reads no cookie and no
session, and its only credential is a bearer token in a header that a browser will not
attach on its own and that a cross-origin page cannot obtain. A hostile page can issue
requests, but only unauthenticated ones — which it could do from a server anyway.

The transport spec's `Origin`-validation requirement targets DNS rebinding against
*localhost* MCP servers, which authenticate ambiently and would otherwise act on a rebound
attacker's behalf. Neither half of that applies to a remote, HTTPS-only, token-only
endpoint.

## Consequences

- A leaked token acts as its owner until revoked, minus deletion. `/admin/einstellungen`
  lists every token with its last use and revokes on one click; tokens expire after a
  year regardless.
- Markdown bodies are rendered with raw-HTML passthrough, because `Bbh.Html.sanitize/1`
  is the security boundary a moment later and escaping first would only mangle legitimate
  markup. The rendered HTML is passed through `Bbh.Html.to_editor/1` before storing, so
  the sanitizer's paragraph merge does not collapse the whole text into one `<p>`.
- No upload path. Photos still go through `/admin/medien`, which sniffs the real file
  type, enforces the megapixel budget and pre-warms variants. MCP can only attach media
  that already exists.
- The per-IP flood guard inherits an app-wide assumption: `BbhWeb.RateLimit.client_ip/1`
  trusts the left-most `X-Forwarded-For` entry. That holds only while the edge proxy
  *replaces* the header rather than appending to it. Production sits behind a central
  Traefik whose configuration lives outside this repository; Traefik's default is to
  overwrite `X-Forwarded-*` for untrusted sources, which is the behaviour relied on here.
  This is not specific to MCP — the same helper guards login, TOTP and magic-link — but it
  is worth stating, since this ADR leans on that limit as the anti-flood control.
- The endpoint is invisible to a client that cannot send a custom header. Claude Code can;
  the Claude app's connector dialog offers OAuth fields only. The token table and the
  `WWW-Authenticate` challenge (which already points at
  `/.well-known/oauth-protected-resource/mcp`) were built for that client, and
  [ADR 0010](0010-mcp-oauth.md) makes it work.
