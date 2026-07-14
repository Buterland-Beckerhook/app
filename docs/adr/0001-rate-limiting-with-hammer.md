# ADR 0001 — Rate limiting with Hammer (ETS backend)

**Status:** Accepted (2026-07-14)

## Context

The authentication and public write surfaces of the Phoenix rewrite were
unthrottled: password login, magic-link login **and** magic-link email
send, the TOTP second-factor challenge, and the public Web-Push
`subscribe` endpoint. That leaves the door open to credential
brute-forcing, magic-link email flooding, TOTP code guessing, and
subscription-table flooding.

The deployment is a **single container** behind Caddy on an internal
Docker network. There is no Redis or other shared cache in the stack, and
adding one purely for rate limiting is not worth the operational cost.

## Decision

Add `{:hammer, "~> 7.0"}` and expose a single wrapper module,
`BbhWeb.RateLimit` (`use Hammer, backend: :ets`), started in the
application supervision tree with a 10-minute clean period. It offers
`check/4` (per-IP + per-action buckets, returns `:ok | {:error, retry_ms}`)
and `client_ip/1` (peer data, honouring `x-forwarded-for` behind the
proxy).

Applied limits:

| Surface | Limit |
|---|---|
| Password login / magic-link login | 10 / 5 min |
| Magic-link email send | 5 / 15 min |
| TOTP verify | 10 / 5 min |
| Push subscribe | 20 / min |

Disabled in dev/test via `config :bbh, BbhWeb.RateLimit, enabled: false`.

## Consequences

- No new infrastructure; buckets live in ETS in the app node.
- State is **per-node**. Correct for the current single-container deploy;
  a horizontal scale-out would require a shared backend (e.g. Redis) or an
  affinity guarantee. Documented here so that trade-off is a conscious one.
- IP attribution depends on the proxy setting `x-forwarded-for`; Caddy
  does this. A misconfigured proxy would bucket all clients together.
