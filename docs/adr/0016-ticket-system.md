# ADR 0016 — Requests go into a Postfach in the app, encrypted, instead of being forwarded

**Status:** Accepted (2026-10-29)

## Context

Contact form, membership form and mail to the club addresses (`vorstand@`, `info@`, …)
ended up in private inboxes: the forms mailed `info@`, and mailcow filter rules
forwarded each club address to the board members' own accounts. That had three costs:

- **Personal data spread out.** A membership application — IBAN, date of birth —
  travelled in clear text to every recipient's private mailbox, with no deletion ever.
- **Nobody knew who answered.** Several people got the same mail; whether and how it
  was answered was invisible to the others.
- **Forwarding relayed spam** that rspamd had not caught, under our domain's
  reputation.

## Decision

**One Postfach in the app** (`Bbh.Tickets`, `/admin/postfach`). Every request — form
or mail — becomes one ticket in a queue; the people granted that queue work it,
admins read everything. Replies go out from the system, as the club address.

- **Queues are data** (`ticket_queues`, maintained by admins — a new address such as
  `insta@` must not need a release), **grants are a table** (`queue_grants`) set per
  user in the user administration, independent of the content role. A new role „Nur Postfach" (`tickets`) has no content access at all. `queue_key`
  is a plain string so admin-defined groups can later share the column.
- **Personal data is encrypted at rest** (`Bbh.Vault`, AES-256-GCM via `:crypto`), each
  value bound to table, column and row id (AAD), so a dump or backup is unreadable
  without the key and a ciphertext cannot be moved between rows. Lists and filters run
  on plain columns only; the sender is found again through an HMAC blind index. This
  protects dumps and backups, not a compromised running app — key and data share the
  host. The keys live outside the backup, in the club's password manager.
- **The Postfach needs a strong session.** Passkey, or magic link plus TOTP — the
  method is stored on the session token, so it survives remember-me and reissue.
- **Mail arrives by IMAP polling** from one collector mailbox (`tickets@`); the queue
  addresses are its aliases, routed by the top-most `X-Original-To`. A minimal own
  IMAP client (`Bbh.Imap`) — no Elixir library covers move/delete with a track record,
  and one known server needs ~10 commands. MIME decoding is gen_smtp's `:mimemail`
  with a small `:iconv` module for charsets.
- **The server copy goes once work starts.** Imported mail waits in
  `Tickets/Importiert` until the ticket leaves `new`, then it is deleted (spam: moved to
  `Junk`, so rspamd learns). From then on the encrypted database row is the only copy.
- **Replies go through their own mailbox** (`tickets@`, `Bbh.TicketMailer`), not the
  system sender `noreply@`: bounces land in the Postfach and are noted on the ticket,
  and a leaked `noreply@` password cannot send as `vorstand@`. Threading by our
  `Message-ID`, or by the `[#BB-…]` subject token only from the original sender.
- **Staff mails carry no personal data** — queue, reference and link only: they end up
  on phones and in forwarded mail. Reminders are bundled, at most one per person and
  day; thresholds are a site setting. Retention is env, not a setting: it is stated
  in the Datenschutzerklärung and must not change by a click.
- **The membership application keeps an electronic record** instead of a signature —
  time, client IP (from the trusted proxy only), Altcha result, and a hash of the
  mandate text shown — and prints as a PDF in the paper form's layout (Typst CLI,
  generated per download, never stored).

## Consequences

- The old mail path stays until `TICKETS_ENABLED=true`; switching means creating
  `tickets@`, then pointing the queue aliases at it and removing the forwarding rules.
- Losing the keys loses every ticket; rotation is `TICKET_KEYS` + `TICKET_KEY_CURRENT`
  and `Bbh.Release.rekey_tickets/0`.
- Beta must have its own keys, its own mailbox, `TICKET_ADDRESS_PREFIX=beta.` (Beta
  gets Prod's queue list with every sync) and no ticket rows
  (`deploy/sync-data.sh` truncates them): a Beta poller with Prod's credentials would
  take and delete real mail.
- A dev database restored from a Prod snapshot carries tickets the dev keys cannot
  read; truncate the ticket tables after such a restore.
