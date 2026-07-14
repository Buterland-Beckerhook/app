# ADR 0003 — Altcha proof-of-work hardening (signed expiry + ETS replay cache)

**Status:** Accepted (2026-07-14)

## Context

The contact form uses a self-hosted Altcha proof-of-work challenge instead
of a third-party captcha. As first built, a solved challenge was
**replayable** (the same payload could be submitted repeatedly) and had no
expiry, weakening it as a spam gate.

## Decision

Harden `Bbh.Altcha`:

- Embed an expiry timestamp in the challenge **salt**, which is folded into
  the signed challenge hash — so a client cannot tamper with it. TTL 300s.
- Bound the accepted solution by the advertised `maxnumber`.
- Record used challenges in `Bbh.Altcha.ReplayCache` — an ETS-backed
  GenServer with a periodic sweep of expired entries; `insert_new` rejects
  any challenge that was already spent.

`ReplayCache` is a **new OTP process** in the supervision tree because it
needs cross-request state with a TTL and a background sweep.

## Consequences

- No external store; the replay cache is in-memory.
- **Single-node only.** Acceptable because the deploy is one container. On
  a restart the cache is cleared — the worst case is that one
  not-yet-expired challenge could be reused once. For a contact-form spam
  gate that is an acceptable trade-off; a clustered or multi-container
  deploy would need a shared/persistent store instead.
