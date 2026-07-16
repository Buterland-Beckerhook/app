# Security Review — feat/phoenix-rewrite

Format: `file:line — SEVERITY — issue — why — fix`

## Executive summary
Solid phx.gen.auth foundation: Argon2, timing-safe password check, session
fixation handled (`renew_session`), CSRF via `:protect_from_forgery`, HSTS/force_ssl
in prod, secrets from env in `runtime.exs`, parameterized queries throughout
(`fragment("? = ANY(?)", ^category, …)` is safe). No `String.to_atom`, no
`binary_to_term`, no SQL interpolation, no unsafe `raw/1` (the only `raw` is a
server-generated QR SVG). Main gaps are missing rate limiting, 2FA changes without
re-auth, Altcha replay, and unauthenticated/unbounded push API.

## WARNING

- `live/user_live/totp.ex:44,53` (+ `router.ex:123`) — WARNING — Enabling and
  **disabling** TOTP requires only an active session, not sudo mode — while
  password/email changes DO require sudo (`settings.ex:4`). A stolen session or
  unattended browser can remove 2FA without re-auth, defeating it. Fix: add
  `on_mount {BbhWeb.UserAuth, :require_sudo_mode}` to `UserLive.Totp`.

- `controllers/totp_controller.ex:12` — WARNING — No rate limiting or attempt
  throttling on the TOTP challenge. With first factor known, a 6-digit code is
  brute-forceable. Fix: rate-limit per pending user/IP (Hammer); lock after N fails.

- `live/user_live/login.ex:106-125` + `user_session_controller.ex:31` — WARNING —
  No rate limiting on password login or magic-link requests → password brute force
  and email-bombing/enumeration timing. Fix: Hammer limit per IP+email.

- `bbh/altcha.ex:32-47` — WARNING — Challenge has no expiry/nonce store; a valid
  payload can be **replayed** indefinitely, so the PoW gives no real spam
  protection on `/kontakt`. Also `number` isn’t bounded by `maxnumber`. Fix:
  embed+verify an expiry in the signed challenge and record used challenges
  (short-TTL cache) to reject replays.

- `controllers/api/push_controller.ex` + `notifications.ex:14` — WARNING — `POST
  /api/push/subscribe` is unauthenticated and unthrottled; anyone can flood
  `push_subscriptions`, and `notify/2` later POSTs to the attacker-controlled
  `endpoint` (SSRF surface to internal hosts). `unsubscribe` lets anyone remove any
  known endpoint. Fix: rate-limit, validate endpoint is https + known push-service
  host allowlist, cap rows.

- `media/upload.ex` + `media.ex:78-106` / `live/admin/media_live/index.ex:36` —
  WARNING — Upload trusts client extension/`client_type`; no magic-byte
  verification. `content_type` is derived only from extension. `@content_types`
  serves `.svg` as `image/svg+xml` inline from app origin → stored XSS if a
  malicious SVG ever lands in the media dir (import task / manual). Fix: validate
  magic bytes; never serve SVG inline (force `Content-Disposition: attachment` or
  sanitize); add CSP.

- `endpoint.ex` / `router.ex` — WARNING — No Content-Security-Policy header
  (`put_secure_browser_headers` doesn’t add one). Site serves user media and Trix
  rich content. Fix: add a CSP via `put_secure_browser_headers(%{"content-security-policy" => …})`.

## SUGGESTION

- `media.ex:151` — SUGGESTION — Path-traversal guard is a `String.contains?(key,
  "..")` blocklist. Router decoding makes it OK today, but prefer
  `Path.safe_relative(key, uploads_dir())` for robustness.

- `bbh/contact.ex:40-41` — SUGGESTION — `name` is interpolated into `subject` and
  reply-to display name unsanitized. Swoosh encodes headers, but strip CR/LF from
  `name` to be safe against header injection. (`email` is regex-safe.)

- `live/admin/user_live/index.ex:39,44` — SUGGESTION — `set_role`/`delete` rely on
  mount-only `:require_admin` (acceptable for LiveView). No guard against an admin
  removing their own admin role → self-lockout (availability). Consider blocking
  demotion of the last admin.

- `notifications.ex` / TOTP login — SUGGESTION — TOTP uses `NimbleTOTP.valid?`
  without the `:since` option; a code is reusable within its 30s window. Track last
  successful TOTP timestamp to prevent same-window replay.

- `runtime.exs:53` — SUGGESTION — DB `ssl: true` commented out. Fine if DB is on a
  private network; otherwise enable.

## Checked clean
Argon2 hashing + `no_user_verify` timing safety, session fixation/renewal,
remember-me cookie (signed, Lax, http_only default), CSRF + secure headers,
force_ssl/HSTS, secrets in env, redacted fields (`password`, `hashed_password`,
`totp_secret`), Ecto parameterization, admin route gating (`require_authenticated`
+ `require_admin`), no `String.to_atom`/`binary_to_term`/raw-SQL/unsafe-`raw`.

## Tools to run manually (no Bash here)
`mix sobelow --exit medium`, `mix deps.audit`, `mix hex.audit`.

---

# Article features review (logo fallback, preview-image switch, gallery lightbox)

Scoped to NEW code in the three article features. **No confirmed or plausible
vulnerabilities found in the new code.** Note: CSP now EXISTS
(`plugs/csp.ex`), superseding the "no CSP" WARNING above for these features.

## 1. Authorization / IDOR — `set_article_preview_image/2` — CLEAN
- `content.ex:139-150`, handler `live/admin/article_live/form.ex:77-85`.
- Client-supplied `img_id`, but BOTH the reset (`update_all set: false`) and the
  flip are scoped `where: i.article_id == ^article_id` (article from
  `socket.assigns.article`, loaded in mount). Flip also requires
  `i.id == ^image_id AND i.article_id == ^article_id`; a foreign image ⇒
  `count == 0` ⇒ `{:error, :not_found}`. Cross-article flip is impossible.
- Route behind `live_session :admin, require_authenticated` (`router.ex:84`) +
  `:require_authenticated_user` pipeline. Flat editor model — mount-level gate is
  the intended and sufficient authority; no per-record ownership expected. Adequate.

## 2. Stored/reflected XSS — gallery lightbox — CLEAN
- `article_html/show.html.heex:45-52`, `assets/js/app.js:86-95`.
- `data-lightbox-alt={image_alt(img)}` (admin-entered title) and `data-lightbox-src`
  are HEEx attribute-escaped on render — no attribute breakout.
- In JS the values reach only `img.src = …` and `img.alt = …`. Assigning a string
  to `.alt` is never HTML-parsed. `.src` on an `<img>` does not execute
  `javascript:` URLs (image-fetch context, not navigation). No `innerHTML` sink for
  the attribute values. No DOM-based XSS in the delegated click handler.

## 3. CSP — runtime style + dialog injection — CLEAN
- `assets/js/app.js:71-85`, `plugs/csp.ex:38,40`.
- The `<style>` element (createElement + `textContent` + appendChild) is governed
  by `style-src 'self' 'unsafe-inline'` → permitted.
- `dialog.innerHTML = '<img alt="">'` is a static literal — no injection.
- Lightbox code runs from the nonce'd, `'strict-dynamic'`-trusted app.js bundle and
  injects no inline `<script>`. No CSP bypass introduced.

## 4. `media_url` / storage_key injection — CLEAN (new code)
- `format.ex:48-56`. `w`/`h` are integers from code via `URI.encode_query`.
  `storage_key` is interpolated raw into `/media/#{key}` but is server-generated by
  `Bbh.Media` (not user-controlled here) and only ever used as an `<img>` src.
- Pre-existing nit (out of scope): `format.ex:54` doesn't `URI.encode` the key —
  harmless today; the place to harden if key generation ever loosens.
