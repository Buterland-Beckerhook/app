---
name: strict-csp-no-inline-handlers
description: Prod CSP uses nonce + strict-dynamic with no unsafe-inline for scripts — inline event handlers (onclick, onfocus…) are blocked in prod but silently pass dev and the test suite
metadata:
  type: project
---

`BbhWeb.Plugs.CSP` (app/lib/bbh_web/plugs/csp.ex) sets `script-src 'nonce-…' 'strict-dynamic'` with **no `'unsafe-inline'`**. Inline HTML event-handler attributes (`onclick="…"`, `onfocus="…"`, etc.) count as inline script and are **blocked in production** — a nonce cannot attach to an attribute handler and `strict-dynamic` does not cover them.

**Why:** CSP is `enabled: false` in `config/dev.exs` (so LiveReload works), so inline handlers *appear* to work while developing. In **test** the plug is `enabled: true` (inherited from `config/config.exs`; neither `config/test.exs` nor `ConnCase` turns it off) — but that changes nothing, because ExUnit renders HTML and never executes JavaScript. A blocked handler therefore passes every HTML-assertion test too. The breakage only manifests in prod as a silent no-op plus a console CSP violation.

**How to apply:** When reviewing HEEx/templates, flag any `on*="…"` inline handler as a prod defect. The CSP-safe fix: register a delegated listener in `app/assets/js/app.js` (loaded nonced on every page via root.html.heex, so it works on both dead controller views and LiveView) keyed off a `data-*` attribute, or a `phx-hook` for LiveView-only surfaces. See existing delegated patterns in app.js (`document.addEventListener("click", … closest("[data-lightbox-src]"))`, `select[data-nav-select]`, and the `MediaTree`/`MediaGrid` drag & drop hooks).

**Regression net:** `test/bbh_web/plugs/csp_test.exs` pins the policy itself (nonce + `strict-dynamic`, no `'unsafe-inline'`, per-request nonce). It cannot catch an inline handler — only a weakening of the policy that would let one through. For the handlers themselves the check stays a `refute html =~ ~r/\son\w+=/`-style assertion in the relevant view test (see `media_live_test.exs`).
