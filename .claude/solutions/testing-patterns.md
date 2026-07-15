# Solutions — ExUnit/LiveView testing patterns (feat/phoenix-rewrite)

Reusable patterns captured while backfilling the test suite (132 → 245 tests).

## Testing context code that spawns DB-touching Tasks (`Task.async_stream` + `Repo`)

**Problem:** `Bbh.Notifications.notify/2` runs `Task.async_stream(&send_one/2)`; the
spawned task processes call `Repo.delete`. Under the default async ExUnit sandbox each
test owns a *private* connection, so spawned processes have no DB connection → ownership
error.

**Solution:** Use `use Bbh.DataCase` **without** `async: true`. `setup_sandbox` starts the
owner with `shared: not tags[:async]`, i.e. **shared mode** for non-async suites, which lets
spawned processes borrow the test's connection. Confirmed in `test/support/data_case.ex:39`.

## Testing an SSRF/host-allowlist prune path without real network I/O

**Problem:** `notify/2` would POST to real push endpoints; can't hit the network in tests.

**Solution:** Seed **only** an *untrusted*-endpoint subscription (e.g. `https://169.254.169.254/…`)
directly via a fixture that bypasses the context's `subscribe/1` validation. `send_one/2` then
always takes the prune branch (`valid_push_endpoint?` false → `Repo.delete`) and never reaches
the HTTP client. Assert the row is gone. See `notifications_test.exs` "prunes … untrusted".

## Testing magic-byte upload validation (LiveView `allow_upload`)

**Problem:** `Media.store_file/2` sniffs magic bytes and rejects spoofed extensions; needs a
real image and a real non-image, plus a writable uploads dir.

**Solution:**
- Embed a 1×1 transparent PNG as base64 and `Base.decode64!` it:
  `iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAAC0lEQVR42mNk+M9QDwADhgGAWjR9awAAAABJRU5ErkJggg==`
- Override `:bbh, :uploads_dir` to a unique tmp dir in `setup` with `on_exit` restore; make the
  suite `async: false` (global app-env mutation). ExUnit never runs async/non-async suites
  concurrently, so no leakage.
- Drive the LiveView flow with `file_input/4` + `render_upload/2`, then
  `element(lv, "#upload-form") |> render_submit()`. Happy path = valid PNG; rejection path =
  bytes `"not an image"` with a `.png` name/`image/png` type (client accept passes on extension,
  server rejects on bytes). See `media_live_test.exs` "upload flow".

## Testing TOTP LiveView (enable/disable + sudo mode)

- **Recover the secret** from the rendered page via a **stable selector**, not a CSS class:
  the template exposes `<span id="totp-secret">{Base.encode32(secret, padding: false)}</span>`;
  test does `Regex.run(~r{id="totp-secret"[^>]*>([A-Z2-7]+)<}, html)` → `Base.decode32!/2` →
  `NimbleTOTP.verification_code/1`. (First-match CSS-class scraping is fragile — a second
  `font-mono` span would silently mismatch.)
- **Sudo-mode redirect:** `@tag token_authenticated_at: DateTime.add(now, -30, :minute)` —
  `register_and_log_in_*` forwards `:token_authenticated_at` into the session token, so the
  `require_sudo_mode` on_mount redirects to `/users/log-in`.

## Prefer driving the real control over `render_hook`

For `phx-change`/`phx-submit` handlers, drive the actual element
(`element(lv, "#role-#{id}") |> render_change(%{...})`) rather than `render_hook(lv, "event", …)`.
`render_hook` bypasses the template, so a renamed event or changed param-key regression slips
through. (Requires the form to carry a stable `id` — added `id="role-#{u.id}"` and
`id="media-filter"` for exactly this.)

## Async controller/context suites — what's safe

Flipping `accounts_test.exs` / `page_controller_test.exs` to `async: true` is safe here because:
Swoosh uses `Swoosh.Adapters.Test` (per-process mailbox, not global), the Hammer rate limiter is
disabled in `config/test.exs`, and the altcha HMAC key is only mutated inside `async: false`
describes. Anything mutating global app-env (`:uploads_dir`, `:altcha_hmac_key`) must stay
`async: false`.
