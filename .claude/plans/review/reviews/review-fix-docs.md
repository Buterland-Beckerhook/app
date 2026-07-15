# Documentation Report — review-fix remediation

**Date:** 2026-07-14 · **Scope:** the 5 new modules + architectural decisions from
commits `9c004b8` (implementation) and `e9ddcd8` (tests) on `feat/phoenix-rewrite`.

## Module / function doc coverage — PASS (no changes needed)

All new modules already ship with `@moduledoc`, and public functions with a
non-obvious contract already have `@doc`:

| Module | `@moduledoc` | Public API docs |
|---|---|---|
| `Bbh.Altcha.ReplayCache` | ✅ | `put_new/2` ✅ (`start_link/1` is standard) |
| `Bbh.Html` | ✅ | `sanitize/1` — see note below |
| `BbhWeb.Plugs.CSP` | ✅ | `init/2`,`call/2` are Plug callbacks (no `@doc` needed) |
| `BbhWeb.Plugs.Health` | ✅ | `init/2`,`call/2` are Plug callbacks |
| `BbhWeb.RateLimit` | ✅ | `check/4` ✅, `client_ip/1` ✅ |

**`Bbh.Html.sanitize/1`** was intentionally left without `@doc`: there is no
direct unit test asserting its scrub contract (it is only exercised indirectly
through the changeset sanitize-on-save tests). Per the documentation Iron Law
"do not add `@doc` to untested code," the `@moduledoc` is sufficient until a
direct test pins the contract. **Suggested follow-up:** add a focused
`Bbh.HtmlTest` (keeps `<h1>/<strong>/<a>`, drops `<script>`/`onerror`), then
document `sanitize/1`.

## ADRs created

No ADR convention existed (no `docs/` tree; `app/AGENTS.md` is framework
guidance, not a decision log). Established `docs/adr/` and recorded the three
decisions whose **why** is not visible in the code — both new dependencies and
the new OTP process:

- `docs/adr/0001-rate-limiting-with-hammer.md` — new dep `hammer`; ETS backend
  chosen for the single-container deploy; per-node state trade-off noted.
- `docs/adr/0002-sanitize-trix-html-on-write.md` — new dep `html_sanitize_ex`;
  sanitize-on-write vs on-render rationale; `raw/1` sites now safe.
- `docs/adr/0003-altcha-replay-cache.md` — new GenServer `Bbh.Altcha.ReplayCache`;
  why in-memory ETS is acceptable (single node), restart-window trade-off.
- `docs/adr/README.md` — index.

## README — no change

The remediation is internal hardening (rate limiting, sanitization, health
checks, CSP, upload validation), not a new user-facing feature, so no README
section was warranted.

## Status: uncommitted

The `docs/adr/` files are written but **not committed** — left for review since
the request sequenced "commit, then document."
