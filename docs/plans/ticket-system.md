# Ticket system ("Postfach") — implementation plan

Status: plan, not yet implemented · 2026-10-29
Target repo: `Buterland-Beckerhook/app` · implementation locally with Claude Code
Later condensed into
`docs/adr/0016-ticket-system.md` + an AGENTS.md section.

## 1. Goal

Replace "contact form / membership form / direct mail → `xxx@` → mailcow filter rule →
private addresses of board members" with an internal ticket system:

- Every request (contact form, membership application, direct mail to a club address)
  becomes **one ticket** in a **queue**.
- Only users granted that queue see and handle it; admins can read everything.
- Somebody takes the ticket, works on it, replies **from the system** (via the club
  address), sets a follow-up date or closes it. Until then, reminders go out.
- Personal data stays on our server (encrypted at rest in the DB); notification mails
  contain **no personal data**, only queue + ticket number + link.
- Nothing is forwarded anymore → no unrecognised spam is relayed → no reputation damage.

Non-goals: a general helpdesk, SLAs, customer portal, full-text search over ticket
content, HTML mail rendering.

## 2. Preparatory PRs (independent, small, ship first)

### 2.1 German texts for account communication (`fix:`)

Still English today:

- `Bbh.Accounts.UserNotifier`: subjects/bodies "Log in instructions",
  "Confirmation instructions", "Update email instructions".
- Flashes: `UserSessionController` ("The link is invalid or it has expired.",
  "Logged out successfully."), `UserLive.Confirmation` ("Magic link is invalid…"),
  `BbhWeb.UserAuth` ("You must log in to access this page.", "You must re-authenticate…").
- Dev hint in `UserLive.Login` ("You are running the local mail adapter.") — optional.

Hardcode German like the rest of the site (no gettext). Sender display name via
`Mailer.sender_name/0`. The ticket notifications in §8 reuse the same notifier style.

### 2.2 Login log (`feat:`)

New table `auth_events`: `user_id` (nullable for unknown e-mail), `event`
(`magic_link_sent`, `login_succeeded`, `login_failed`, `totp_failed`, `passkey_failed`,
`logged_out`), `method` (`passkey` | `magic_link` | `magic_link_totp`), `ip`,
`user_agent` (truncated to 255), `inserted_at`.

- Written from `UserSessionController`, `TotpController`, `UserLive.Login` (passkey),
  `UserAuth.log_out_user/1`.
- Admin view: new tab in the user administration (`/admin/benutzer/:id` or a tab on the
  index), last 90 days, newest first.
- Pruned by `Bbh.Workers.AuthPruner` after `AUTH_LOG_RETENTION_DAYS` (default 90).
- Mention in the Datenschutzerklärung (purpose: security of the admin area).

### 2.3 Strong authentication gate (`feat:`)

Today `/users/security` is only a **nudge** after a magic-link login
(`maybe_put_enrollment_return_to/2`); a user without passkey/TOTP can still work.

- Store the login method in the session (`:auth_method`), set wherever
  `log_in_user/3` is called.
- New `on_mount {BbhWeb.UserAuth, :require_strong_auth}` (+ plug equivalent for the
  attachment download controller): passes only if the session was established with
  `passkey` or `magic_link_totp`. Otherwise redirect to `/users/security` with a German
  flash ("Für das Postfach ist eine Anmeldung mit Passkey oder Zwei-Faktor-Code nötig.").
- Applied to all ticket routes only (content editing unchanged for now — could be widened
  later).

### 2.4 One trustworthy client IP (`fix:`)

The client IP is resolved in two places today, both taking the **left-most**
`X-Forwarded-For` entry: `BbhWeb.RateLimit` and `UserLive.Login`. The left-most entry is
whatever the client sent and can be forged — that lets a client pick its own rate-limit
bucket, and it would make the IP in the login log (§2.2) and the membership submission
record (§6.1) worthless as evidence.

- New `BbhWeb.ClientIp.get/1` (conn) and a LiveView variant via `connect_info`
  (`:peer_data`, `:x_headers`). Rule: use the entry appended by our own proxy — the
  **right-most** `X-Forwarded-For` entry when the peer is the trusted proxy (Traefik on
  the Docker network), otherwise `conn.remote_ip`.
- Verify Traefik's `forwardedHeaders` configuration on the host (whether it passes on or
  replaces a client-supplied `X-Forwarded-For`) and add a test for a forged header.
- Rate limit, login log, membership record all use the helper.

## 3. Queues

Fixed list in code (like `Bbh.Calendar.Event.calendars/0`), module `Bbh.Tickets.Queue`:

| key             | label            | inbound address (env-overridable)        | replies sent as | in contact form |
| --------------- | ---------------- | ---------------------------------------- | --------------- | --------------- |
| `info`          | Allgemein        | `info@buterland-beckerhook.de`           | `info@`         | yes (default)   |
| `vorstand`      | Vorstand         | `vorstand@…`                             | `vorstand@`     | yes             |
| `offiziere`     | Offiziere        | `offiziere@…`                            | `offiziere@`    | yes             |
| `jungschuetzen` | Jungschützen     | `jungschuetzen@…`                        | `jungschuetzen@`| yes             |
| `kinderfest`    | Kinderfestausschuss | `kinderfestausschuss@…`               | `kinderfestausschuss@` | yes      |
| `webmaster`     | Website          | `webmaster@…`                            | `webmaster@`    | **no** (mail only) |
| `mitgliedschaft`| Mitgliedsanträge | — (membership form only)                 | `vorstand@`     | no              |

Each queue has an inbound address (nil for `mitgliedschaft`) and a reply address
(`Queue.reply_address/1`); for `mitgliedschaft` the reply address is `vorstand@`.

Grants (set in the user administration, not hardcoded):

- `info` (Allgemein, default in the form): Vorstand + the leaders of the Offiziere
  (Oberst etc.) — i.e. the people who today receive `vorstand@` **and** the officers'
  leadership. Granted explicitly per user, **not** derived from the `vorstand` /
  `offiziere` grants, because not every officer should see general requests.
- `mitgliedschaft`: geschäftsführender Vorstand only. It is its own queue because it
  carries IBAN, date of birth and the client IP (§6.1).

Addresses: `TICKET_QUEUE_ADDRESSES="info=info@…,vorstand=vorstand@…,…"` with the table
above as default. The address is used for routing inbound mail (§6.2) and as sender of
replies (§7).

## 4. Permissions

- **Grants live in their own table** (decided 2026-10-29), not as an array on `users`
  like `users.calendars`:

  ```
  queue_grants
    user_id    uuid → users, on_delete: :delete_all
    queue_key  string           -- validated against Queue.keys/0 for now
    inserted_at, granted_by_id (uuid → users, nilify)
    unique (user_id, queue_key), index on queue_key
  ```

  Why: "who handles queue X" becomes a plain indexed query (notifications, reminders,
  digest), grants are auditable (`granted_by_id`, timestamp), and later admin-defined
  groups (Festausschuss etc., see `event-registration-idea.md`) can be referenced by the
  same `queue_key` without migrating ticket data. `queue_key` is deliberately a string,
  not an FK, so fixed code queues and future DB groups share one column; validation
  moves from `Queue.keys/0` to "fixed key or existing group" at that point.
- Context `Bbh.Tickets.Grants`: `list_queue_keys(user)`, `list_users(queue_key)`,
  `set_grants(admin_scope, user, keys)` (replace-all in one transaction, writes
  `ticket_events`-style audit row `grants_changed` without personal data). Load the
  user's keys once into `Bbh.Accounts.Scope` (new field `ticket_queues`) on mount so
  authorization checks stay in-memory.
- Edited in the user administration as checkboxes (like calendars).
- Grants are **independent of the content role**. A board member who never edits
  content needs a role without content access → add role `tickets` (label
  "Nur Postfach"): no content sections, no calendars unless granted.
  `users_role_valid` check constraint must be extended.
- `BbhWeb.Authz`:
  - `can_access_section?(scope, :tickets)` → admin or `scope.ticket_queues != []`
  - `can_view_ticket?(scope, ticket)` → admin or `ticket.queue in scope.ticket_queues`
  - Note: `Authz` takes a `%User{}` today; ticket checks need the scope (grants are on
    it). Either pass the scope for the ticket functions only, or preload grants into a
    virtual field on `User`. Prefer the scope — it is what LiveViews already carry.
  - `can_handle_ticket?(user, ticket)` → same as view (admins: yes, they are the
    shadow reader and can step in)
  - `can_delete_ticket?(user, _)` → admin only (soft delete, §10); restore admin only
  - `webmaster` queue: admins implicitly; others only if granted
- Admins receive no per-ticket notifications for queues they are not granted; they get
  the daily digest (§8.3).
- All ticket routes: `:require_authenticated_user` + `:require_strong_auth` (§2.3).

## 5. Data model

All personal data in `*_enc` columns (encrypted, §5.1). Plain columns carry only what
lists, filters, reminders and retention need.

### `tickets`
| column | type | note |
|---|---|---|
| `id` | uuid | |
| `number` | integer, unique | from a Postgres sequence; displayed `BB-2026-0042` (year from `inserted_at`) |
| `queue` | string | check constraint |
| `kind` | string | `contact` \| `membership` \| `email` |
| `status` | string | `new` \| `open` \| `waiting` \| `follow_up` \| `closed` \| `spam` |
| `assignee_id` | uuid → users, nilify | |
| `follow_up_on` | date | required when `status = follow_up` |
| `last_activity_at` | utc_datetime | any message/note/status change |
| `closed_at`, `deleted_at` | utc_datetime | retention (§10) |
| `subject_enc` | binary | |
| `requester_name_enc`, `requester_email_enc` | binary | |
| `requester_email_hmac` | binary, indexed | blind index → "weitere Tickets dieses Absenders", threading fallback |
| `payload_enc` | binary | structured form data (membership fields as JSON) |
| `spam_score` | float | from rspamd header (§6.3), nil for forms |
| timestamps | | |

### `ticket_messages`
`id`, `ticket_id` (cascade), `direction` (`in` \| `out` \| `note` \| `system`),
`author_id` (user, for out/note), `from_enc`, `to_enc`, `body_enc` (text only),
`message_id` (outbound: our generated `<uuid@buterland-beckerhook.de>`; inbound: SHA-256
of the header value), `in_reply_to` (same hashing for inbound), `imap_mailbox`,
`imap_uidvalidity`, `imap_uid`, `server_copy_removed_at`, `inserted_at`.
Unique index on `(imap_mailbox, imap_uidvalidity, imap_uid)` and on inbound
`message_id` → idempotent import.

### `ticket_attachments`
`id`, `message_id` (cascade), `filename_enc`, `content_type` (as sent, informational
only), `size`, `data_enc` (bytea). Stored in the DB on purpose: one encryption path,
covered by the existing nightly dump, deleted with the ticket. Limits: 10 MB per file,
25 MB per mail (env), larger parts are dropped with a `system` message on the ticket.

### `ticket_events` (history + access log)
`id`, `ticket_id` (nilify on hard delete), `ticket_number` (kept after purge),
`user_id`, `action` (`viewed`, `assigned`, `status_changed`, `replied`, `noted`,
`attachment_downloaded`, `marked_spam`, `deleted`, `restored`, `server_copy_removed`),
`meta` (jsonb — **never personal data**: old/new status, assignee id), `inserted_at`.
`viewed` is written at most once per user/ticket per 10 minutes.

## 5.1 Encryption

Goal (agreed): ticket data unreadable in a DB dump / backup. Not a goal: protection
against a compromised running app (key and data are on the same host).

- `Bbh.Vault`: AES-256-GCM via `:crypto.crypto_one_time_aead/6` (no new dependency).
  Ciphertext format: `<<format::8, key_id::8, iv::binary-12, tag::binary-16, ct::binary>>`,
  fresh random 96-bit IV per value.
- AAD = `"<table>.<column>:<row id>"` → a ciphertext copied into another row/column
  fails to decrypt. Requires the row id before insert (uuid generated in the changeset /
  `Ecto.UUID.generate/0`).
- Ecto types `Bbh.Encrypted.Binary`, `Bbh.Encrypted.String`, `Bbh.Encrypted.Map`
  (JSON) — or explicit encrypt/decrypt in the context if AAD-with-row-id is awkward in a
  type. Decide during implementation; contexts are the only place that sees clear text.
- Blind index: `HMAC-SHA256(TICKET_HMAC_KEY, normalize(email))`.
- Keys from env:
  - `TICKET_KEYS="1:<base64 32 bytes>,2:<base64 32 bytes>"`
  - `TICKET_KEY_CURRENT=2` (new writes); old ids stay readable
  - `TICKET_HMAC_KEY=<base64 32 bytes>`
  - `mix bbh.vault.gen_key` prints a key; `Bbh.Release.rekey_tickets/0` (built on `Bbh.Vault.rekey/2`, added with the ticket tables) re-encrypts
    everything with the current key (rotation), callable via `bin/bbh eval`.
- Boot check: if `TICKETS_ENABLED=true` and keys are missing/invalid → refuse to start
  (better than silently storing clear text).
- **Key backup:** the keys must be stored outside the server backup (club password
  manager, two people). `deploy/backup.sh` backs up dump + uploads only, not `.env`
  — keep it that way. Without the key a restored dump is useless; with the key next to
  the dump the encryption is pointless.

Leak paths to close explicitly:

- **Oban job args** live in the DB (and in dumps): pass ticket/message ids only, never
  addresses or text.
- **Logging:** `Mailer.deliver_logged/2` logs `to` and `subject`. Add an option
  (`redact: true`) that logs only the context and the ticket number for ticket mails.
  No `inspect/1` of ticket structs in logs → `redact: true` on all decrypted virtual
  fields.
- Notification mails (§8): no subject text, no name, no sender address.
- Phoenix LiveDashboard / error pages: no ticket params in error reports.

## 6. Ingest

### 6.1 Forms

- `ContactController.create/2`: after validation + spam checks → `Tickets.create_from_contact/2`
  instead of `Contact.deliver/1`. Form gets a recipient select (queues marked "in contact
  form" in §3), default `info`, preselectable via `?an=vorstand` so the club pages can
  link straight to it.
- `MembershipController.create/2`: → `Tickets.create_from_membership/2`, queue
  `mitgliedschaft`, structured fields in `payload_enc`, detail view renders the same
  summary incl. the soft age flags.
- **Submission record** (replaces date + signature on the paper form, used in the PDF,
  §9.1), stored inside `payload_enc`:
  - `submitted_at` (UTC; rendered Europe/Berlin)
  - `client_ip` (from `BbhWeb.ClientIp`, §2.4)
  - `form_version` — SHA-256 (first 12 hex) of the mandate + privacy text shown to the
    applicant, so the PDF can state which wording was accepted; bump the text → new
    hash automatically
  - `sepa_mandate: true`, `altcha_verified: true|false`
  - ticket number (implicit)

  Purpose: proof of the electronically given SEPA mandate and the application.
  Legal basis Art. 6(1)(b)/(f) GDPR; stored only on membership tickets, deleted with the
  ticket (§10); named in the Datenschutzerklärung. Contact tickets do **not** store the
  IP.
- The **confirmation copy to the applicant stays** (it is the SEPA mandate copy) and
  **masks the IBAN** (decided): country code + check digits and the last 4 characters,
  e.g. `DE89 •••• •••• •••• ••30 00` (usual groups of four) (helper `Bbh.Membership.mask_iban/1`, tested with
  short/long IBANs). Name, address, date of birth
  stay (the applicant entered them). Today the full IBAN goes out in clear text.
- The club mail (`deliver_to_club/1`, `Contact.deliver/1`) is removed once the flag is on.
  Today that mail carries the full IBAN to `info@` and from there to private inboxes —
  this alone is a substantial privacy gain.
- Feature flag `TICKETS_ENABLED` (default false) → old mail path stays until switch-over.
- A short confirmation for the contact form ("Ihre Anfrage ist eingegangen") is OK
  (rate-limited by the existing Altcha + timing + honeypot); it must **not** contain the
  message text (an attacker could otherwise use the form to send arbitrary text to any
  address). Recommendation: no confirmation mail for the contact form at all, just the
  flash.

### 6.2 IMAP (mailcow)

**Mailcow setup (recommended):** one collector mailbox `tickets@buterland-beckerhook.de`;
the queue addresses become **aliases** pointing to it; the existing forwarding filter
rules are removed at switch-over. Routing to a queue by the original recipient.

**Routing header (verified on the live mailcow, 2026-10-29):** delivery via alias keeps
the alias in `X-Original-To` (e.g. `X-Original-To: webmaster@…`), while
`Delivered-To` carries the final mailbox. Rules:

- Use the **top-most** `X-Original-To` (Postfix prepends it at delivery; a sender can
  forge further `X-Original-To` headers lower down, they are ignored).
- Match it against the inbound address table (§3) → queue. No match (e.g. mail sent
  directly to `tickets@`) → `info`.
- One mail to several queue aliases (`To: vorstand@, offiziere@`): verify on Beta
  whether mailcow delivers one copy per alias or deduplicates. Either way the unique
  index on the inbound `Message-ID` hash keeps it to **one** ticket — in the queue of
  the first copy imported; other queue addresses found in `To`/`Cc` are recorded as a
  `system` note ("auch adressiert an: Offiziere"), and the ticket can be moved to another
  queue manually (event `queue_changed`).
- `Delivered-To` is only used for loop detection (a mail already delivered to
  `tickets@` once must not be imported again via a forwarding loop).

**Client library — decided: own minimal client** (`Bbh.Imap`). Reasons:

- No Elixir IMAP library with a track record covers what we need: `yugo` documents
  only "notify on new mail" (no move/delete/flags); `plover` covers the commands but is
  very young and self-described as not production-ready.
- We talk to exactly **one** server (mailcow's Dovecot) and need ~8 commands, all with
  well-defined responses — the risky generality of a full client is not needed.
- It stays testable without network: the parser works on recorded transcripts.

Scope: `:ssl` to port 993 with `verify: :verify_peer`, CA store from
`:public_key.cacerts_get/0`, SNI + hostname check; commands `CAPABILITY`, `LOGIN`
(only after TLS), `SELECT`, `UID SEARCH` (by UID range above the last seen UID),
`UID FETCH <uid> (BODY.PEEK[] RFC822.SIZE)`, `UID MOVE` (Dovecot supports `MOVE`;
check `CAPABILITY`, no COPY+EXPUNGE fallback needed), `UID STORE +FLAGS (\Deleted)`,
`UID EXPUNGE`, `CREATE` (for `Tickets/Importiert`), `LOGOUT`. Tagged command/response
loop, literal handling (`{n}\r\n`), `NO`/`BAD` → `{:error, …}`, a size limit per
literal (abort above `TICKET_MAX_MAIL_MB`), timeouts on every recv. Polling only, no
IDLE. Target < 400 lines + tests. Dev compose gets a **Dovecot** container (same server
software as prod) seeded with sample mails, so local tests hit the real protocol.
- MIME parsing: evaluate the `mail` hex package (or similar) for multipart, charsets,
  quoted-printable/base64 and RFC 2047 headers before writing one.

**Poller:** `Bbh.Workers.ImapPoller`, Oban cron every 2 min, `unique` so runs never
overlap. Per message in `INBOX`:

1. Fetch with `BODY.PEEK[]` (no `\Seen` side effect), check `UIDVALIDITY`.
2. Skip if already imported (unique index) → just move it.
3. Loop/bounce protection: drop to `system` handling if `Auto-Submitted` ≠ `no`,
   `Precedence: bulk|list|junk`, sender is one of our own addresses, or `MAILER-DAEMON`.
   A bounce referencing one of our outbound `Message-ID`s becomes a `system` message on
   that ticket ("Antwort konnte nicht zugestellt werden"); anything else is discarded.
4. Threading (§7.2) → append to existing ticket, or create a new ticket.
5. Spam score (§6.3).
6. `UID MOVE` to `Tickets/Importiert` (folder created on first run).

**Server copy lifecycle (agreed: delete as soon as work starts, also in the test
phase):**

- First transition out of `new` (assigned/open/reply/close) → `UID STORE +FLAGS
  (\Deleted)` + `UID EXPUNGE` in `Tickets/Importiert`, set `server_copy_removed_at`,
  event `server_copy_removed`. Done in an Oban job (retry on IMAP failure), never inline
  in the LiveView.
- "Als Spam markieren" → `UID MOVE` to `Junk` instead of deleting, so rspamd learns
  (mailcow trains on moves into Junk via imapsieve — verify it is active).
- Safety net: the job never deletes a message the ticket does not reference by
  mailbox + UIDVALIDITY + UID.

Text handling: use the `text/plain` part; if only HTML exists, convert to text (strip
tags, keep line breaks and link targets as `text (url)`). Never render mail HTML.

Attachments: stored per §5, downloaded via a controller behind
`require_strong_auth`, response with `Content-Disposition: attachment`, sanitized
filename, `Content-Type: application/octet-stream`, `X-Content-Type-Options: nosniff`,
event `attachment_downloaded`. No inline images, no previews.

### 6.3 Spam

- Forms: existing honeypot + timing + Altcha (re-check the contact form actually loads
  the Altcha bundle, see "Lazy JS bundles" in AGENTS.md).
- Mail: mailcow/rspamd already moves high-score mail to `Junk` — the poller reads `INBOX`
  only. Additionally parse `X-Rspamd-Score` / `X-Spamd-Result` (verify header name in
  mailcow); above `TICKET_SPAM_SCORE` (default 6.0) → status `spam`, no notification.
- Spam tickets: visible in a "Spam" filter for the queue, restorable, auto-deleted after
  `TICKET_PURGE_DAYS`.
- No automatic reply to inbound mail ever (backscatter).

## 7. Replies from the system

### 7.1 Sending

- Compose in the ticket view (text only), optional internal note instead.
- `From`: queue address with display name, e.g.
  `"Schützenverein Buterland-Beckerhook – Vorstand" <vorstand@…>`; `Reply-To` the same
  (lands in the collector mailbox via the alias). Sender is `Queue.reply_address/1`, so
  `mitgliedschaft` replies go out as `vorstand@`; an answer to that reply is threaded
  back into the membership ticket via `In-Reply-To`, not routed to the `vorstand` queue.
- Subject: `Re: <original subject> [#BB-2026-0042]` (forms: `Ihre Anfrage [#BB-…]`).
- Headers: own `Message-ID`, `In-Reply-To`/`References` from the last inbound message,
  `Auto-Submitted: no`.
- Signature per queue (configurable later; v1: static per queue + sender's name).
- Sent via Oban job (args: message id). On failure: `system` message on the ticket and a
  flash/notification to the author.
- **Two mail accounts, two jobs:**
  - `noreply@` (exists): system mail only — login links, ticket notifications,
    reminders, digest, the applicant's confirmation copy. Current `SMTP_*` env.
  - `tickets@` (new collector mailbox): IMAP ingest **and** SMTP for replies, new env
    `TICKET_SMTP_USERNAME`/`TICKET_SMTP_PASSWORD` (host/port shared with `SMTP_RELAY`).
    The queue addresses are aliases of this mailbox; mailcow lets a mailbox send from
    aliases that point to it (verify in the current UI under the mailbox's sender
    addresses). Separate Swoosh mailer config (`Bbh.TicketMailer`) so the two
    credentials never mix.
  - Why not everything through one account: bounces. Replies are sent with envelope
    sender = queue alias → bounces land in `tickets@` and are threaded onto the ticket
    (§6.2 step 3); bounces of system mail stay out of the ticket inbox. It also limits
    what a leaked `noreply@` password can do (cannot send as `vorstand@`).
- SPF/DKIM unchanged (same domain, same host).
- Sending a reply sets status `waiting` (default, changeable in the same form).

### 7.2 Threading inbound replies

In order: `In-Reply-To`/`References` matching one of our outbound `message_id`s →
`[#BB-YYYY-NNNN]` token in the subject (number must exist and the sender's blind index
must match the ticket's requester **or** the ticket was never answered — prevents
hijacking by guessing numbers) → otherwise new ticket.

Reply on a `waiting`/`follow_up`/`closed` ticket → status back to `open`, notify
assignee (or the queue if unassigned). Reply to a purged ticket → new ticket.

## 8. Notifications, reminders, digest

All mails via `Bbh.Accounts.UserNotifier`-style module `Bbh.Tickets.Notifier`, German,
to the user's account e-mail, **without personal data**:

> Betreff: Postfach: neue Anfrage (Vorstand)
> Im Postfach „Vorstand" ist eine neue Anfrage eingegangen: BB-2026-0042.
> Bearbeiten: https://buterland-beckerhook.de/admin/postfach/BB-2026-0042

### 8.1 Immediate
- New ticket in queue → all users granted the queue (bundled: job delayed 2 min,
  one mail per user listing all new numbers).
- Inbound reply on a ticket → assignee (or queue if unassigned).
- Assignment by someone else → new assignee.

### 8.2 Reminders (until closed)
Oban cron hourly, but at most **one reminder mail per user per day** (at the configured
hour, default 8 local time), listing numbers + reason:

| condition (default) | to |
|---|---|
| `new` and unassigned > 24 h | all granted users of the queue |
| `open`, no activity > 7 days | assignee |
| `follow_up` and `follow_up_on <= today` | assignee |
| `waiting` > 14 days | assignee ("nachfassen oder schließen") |

### 8.3 Admin digest
Daily, admins only: counts per queue and status, list of overdue numbers, plus an
escalation section for tickets unassigned > 3 days. No per-ticket mails to admins.
Skip the mail when there is nothing to report.

### 8.4 Where the values are configured

Reminder/escalation values are **editable in the admin UI**, not env: new tab
"Postfach" on the existing site settings page (`SiteSettingsLive`, admins only),
stored as new columns on the `site_settings` singleton with the defaults above:

| field | default | validation |
|---|---|---|
| `ticket_reminder_hour` | 8 | 0..23 |
| `ticket_remind_unassigned_hours` | 24 | 1..168 |
| `ticket_remind_idle_days` | 7 | 1..90 |
| `ticket_remind_waiting_days` | 14 | 1..90 |
| `ticket_escalate_days` | 3 | 1..90 |
| `ticket_admin_digest_enabled` | true | |

Env keeps what is infrastructure or legally fixed: keys, IMAP, spam threshold,
attachment limits, retention periods (§11). Retention deliberately stays out of the UI,
because it is stated in the Datenschutzerklärung and should not change by a click.

## 9. Admin UI

- Section "Postfach" (`/admin/postfach`), shown in the nav when
  `can_access_section?(user, :tickets)`; badge with count of `new` in own queues.
- List: filters queue (own queues; admins all), status, "Mir zugewiesen", "Überfällig",
  "Spam"; columns number, **subject**, queue, status, assignee, age, last activity.
  Subjects are decrypted per page (paginate, 50 rows) — filtering and sorting stay on
  the plain columns; no search over subjects. Listing does not write `viewed` events,
  only opening a ticket does.
- Detail: thread (in/out/note/system), "Übernehmen", assign, status, follow-up date,
  reply/note, spam, (admin) delete/restore, "weitere Tickets dieses Absenders"
  (blind index), event history.
- Membership tickets: structured view of the application (+ age flags), field
  "Mitgliedsnummer" (entered by the board, stored in `payload_enc`; it is also the SEPA
  mandate reference), button "PDF herunterladen" (§9.1).
- Dashboard widget: own open tickets.
- User administration: queue checkboxes (like calendars), role "Nur Postfach",
  login log (§2.2).

## 9.1 Membership application as PDF

Layout follows the existing paper form (`/media/2026/915a5624-….pdf`) so the member
administration files online and paper applications the same way:

1. Title "Aufnahmeantrag", note on the annual fee and the debit date (text from the
   paper form; fee/date as constants next to `@creditor_id` in `Bbh.Membership`, or
   better from one place both the online form and the PDF read).
2. "Persönliche Daten des Antragstellers": Nachname | Vorname; Straße und Hausnummer |
   Geburtsdatum; PLZ | Ort | E-Mail-Adresse | Mitgliedsnummer (from the ticket field,
   blank if not yet entered); "Kinder unter 15 Jahren" (Vorname | Geburtsdatum).
3. "SEPA-Lastschriftmandat": Gläubiger-ID, Mandatsreferenz (= Mitgliedsnummer if set,
   else "gleich Mitgliedsnummer"), Kontoinhaber, Kreditinstitut, IBAN (**full** — this
   is the internal copy), BIC, mandate text as shown online.
4. Datenschutz: the paper form has a consent block; the online form deliberately has
   none (Art. 6(1)(b), see `Bbh.Membership`) → print the privacy note as shown online,
   not a consent the applicant never gave.
5. Instead of "Ort, Datum / Unterschrift": a box **"Elektronisch übermittelt"** with
   submission time (Europe/Berlin), IP address, ticket number, form version hash,
   "SEPA-Lastschriftmandat elektronisch erteilt: ja", plus the soft age flags if any.
6. Footer: "Erzeugt am … von <Benutzer>" and page numbers.

Generation:

- **Decided: Typst CLI**, generated on demand from the ticket's form data at download
  time. Shipped in the Docker image exactly like `pmtiles` (pinned version, sha256
  check, `# renovate:` annotation, both Dockerfiles). Template
  `priv/pdf/aufnahmeantrag.typ`; data passed as JSON (verify the CLI's stdin/stdout
  support for the pinned version, otherwise a private temp dir removed in an `after`
  block). Output streamed to the browser, **never stored** (neither in uploads nor in
  the media library). Fonts: embed Barlow from `priv/static` (`--font-path`) so the PDF
  matches the site and does not depend on system fonts.
- Download writes event `pdf_exported`; route behind `require_strong_auth` and
  `can_view_ticket?/2`; `Cache-Control: no-store`.

## 10. Retention

- `TICKET_RETENTION_MONTHS` (default 12): closed tickets are soft-deleted
  (`deleted_at`) this long after `closed_at`.
- `TICKET_PURGE_DAYS` (default 30): soft-deleted (incl. spam) are hard-deleted with
  messages and attachments; `ticket_events` keep `ticket_number`, `ticket_id` nilified.
- `ticket_events` / `auth_events` pruned after `TICKET_EVENT_RETENTION_MONTHS`
  (default 12) / `AUTH_LOG_RETENTION_DAYS` (90).
- `Bbh.Workers.TicketPruner`, nightly via Oban cron.
- Backups: purged data remains in Borg archives for the Borg retention period — state
  this in the Datenschutzerklärung (and it's encrypted twice: Borg + app key).

## 11. Configuration (env, `deploy/.env.example`)

```
TICKETS_ENABLED=false
TICKET_KEYS=1:...
TICKET_KEY_CURRENT=1
TICKET_HMAC_KEY=...
TICKET_QUEUE_ADDRESSES=info=info@buterland-beckerhook.de,vorstand=vorstand@...,...
TICKET_IMAP_HOST=mail.buterland-beckerhook.de
TICKET_IMAP_PORT=993
TICKET_IMAP_USERNAME=tickets@buterland-beckerhook.de
TICKET_IMAP_PASSWORD=...
TICKET_SMTP_USERNAME=tickets@buterland-beckerhook.de
TICKET_SMTP_PASSWORD=...
TICKET_SPAM_SCORE=6.0
TICKET_MAX_ATTACHMENT_MB=10
TICKET_MAX_MAIL_MB=25
TICKET_RETENTION_MONTHS=12
TICKET_PURGE_DAYS=30
TICKET_EVENT_RETENTION_MONTHS=12
AUTH_LOG_RETENTION_DAYS=90
```

(Reminder values: admin UI, §8.4.)

Mail server is on the same Netcup host: the app can reach mailcow's IMAP via the
public hostname (TLS verified); no extra Docker network needed unless preferred.

## 12. Datenschutz

- Datenschutzerklärung: processing of contact/membership data in the club's own system
  on the club server (Netcup), access limited to responsible board members, retention
  periods (§10), backups, login log for admin users, and for membership applications the
  submission time + IP address as proof of the electronic SEPA mandate (§6.1).
- Verarbeitungsverzeichnis: new entry "Anfragenbearbeitung".
- Auskunft/Löschung: blind index finds all tickets of one e-mail address; admin can
  delete them (soft → purge).

## 13. PR breakdown (each green on `mix precommit`, English PR titles/descriptions)

1. `fix: German texts for login and account mails` (§2.1)
2. `fix: resolve client IP from the trusted proxy only` (§2.4)
3. `feat: login event log for admins` (§2.2)
4. `feat: require passkey or TOTP session for sensitive areas` (§2.3)
5. `feat: mask IBAN in the membership confirmation mail` (§6.1) — independent, can go
   right away
6. `feat: Bbh.Vault field encryption with key rotation` (§5.1)
7. `feat: ticket core — queues, permissions, admin inbox, notes, status` (§3–5, §9) +
   forms create tickets behind `TICKETS_ENABLED` (§6.1) incl. submission record
8. `feat: membership application PDF` (§9.1)
9. `feat: ticket notifications, reminders and admin digest` (§8, incl. settings tab)
10. `feat: reply to tickets via the club address with threading` (§7)
11. `feat: IMAP ingest for club mailboxes` (§6.2, §6.3) incl. dev IMAP server in
    `compose.yml` (e.g. GreenMail or a plain Dovecot container) for local tests
12. `feat: ticket retention and purge` (§10)
13. `docs: ADR 0016 ticket system, AGENTS.md section, .env.example`

### Beta isolation (important once tickets exist)

Beta runs on a copy of Prod data. With tickets that copy would contain personal data,
and a Beta poller with Prod credentials would **steal and delete** real mails.

- Beta gets its **own** keys (never Prod's) → copied ticket rows are unreadable there.
  Better still: the copy step truncates `tickets`, `ticket_messages`,
  `ticket_attachments`, `ticket_events`, `auth_events` (in the Beta restore path, or a
  `Bbh.Release.scrub_personal_data/0` run right after restore).
- Beta uses its own test mailbox (`tickets-beta@` + test alias), never `tickets@`.
- The poller and reply sending start only if their env is set explicitly; no fallback
  to the Prod values.

### Switch-over on Prod

Keys generated and stored in the password manager → Beta test with its own mailbox →
`tickets@` mailbox created, `TICKET_SMTP_*` set → flag on (forms create tickets) →
queue addresses switched from forwarding rules to aliases of `tickets@` → old filter
rules removed → check `Junk` and `Tickets/Importiert` during the first weeks.

## 14. Tests (minimum)

- Vault: round-trip, wrong AAD fails, old key id still decrypts, rekey.
- Authz: queue grants (table, unique per user/queue, cascade on user delete,
  replace-all is atomic), admin read-all, role `tickets` has no content access, strong-auth
  gate redirects magic-link-only sessions.
- Forms: ticket created in the right queue, no club mail when flag on, IBAN masked in
  applicant copy, no PI in Oban args (assert on `Oban.Job.args`).
- IMAP: parser on recorded transcripts (literals, multi-line, NO/BAD), idempotent import,
  loop/bounce rules, routing by header, spam threshold, server copy removed on first
  status change, spam → Junk move.
- Threading: In-Reply-To match, subject token with/without matching sender, reopen.
- Reminders: one mail per user/day, correct conditions, no PI in body/subject.
- Retention: soft delete after N months, purge after N days, events keep number.

## 15. Decisions (2026-10-29)

- `mitgliedschaft` → geschäftsführender Vorstand; replies from `vorstand@`.
- Membership export as PDF in the layout of the paper form; submission time + IP
  instead of date/signature.
- KFA address `kinderfestausschuss@`; `webmaster` not selectable in the contact form.
- `info` (Allgemein) is the form default and goes to Vorstand + Offiziersleitung
  (explicit grants).
- IBAN masked in the applicant's confirmation mail.
- Subject shown in the ticket list.
- Reminder defaults OK, editable in the admin UI.
- PDF via Typst CLI, generated on download.
- Own minimal IMAP client against Dovecot.
- Routing by top-most `X-Original-To` (verified).
- mailcow learn-on-move-to-Junk is active (confirmed).
- `tickets@` for IMAP + replies (sending as its aliases), `noreply@` stays for system
  mail.
- Queue grants in their own table `queue_grants` (§4), prepared for admin-defined
  groups later.

## 16. Still open

1. Traefik: test with a forged `X-Forwarded-For` whether it is passed on or replaced
   (§2.4) — together with the planned Traefik v3 upgrade on the host.
2. mailcow: one copy or deduplication when a mail goes to two queue aliases at once;
   confirm `tickets@` may send as its aliases.
