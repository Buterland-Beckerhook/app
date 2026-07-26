---
name: liveview-hook-payload-trust
description: Admin LiveViews take ids from JS hook pushEvent payloads, not just server-rendered phx-value — check every context function on that path tolerates non-UUID input (reads raise Ecto.Query.CastError, writes raise Ecto.ChangeError)
metadata:
  type: project
---

Admin LiveViews in this repo increasingly receive **ids straight from the browser** via
`this.pushEvent(...)` in `app/assets/js/app.js` hooks (media drag & drop, and the URL
`?folder=` query param before it). That is a different trust level from `phx-value-id`
on a server-rendered button, and Ecto's `binary_id` handling is the trap — with **two
distinct failure modes**, both verified against this app's schemas:

- **Read path:** a non-UUID string in a query `where` raises `Ecto.Query.CastError`
  (`Media.get_upload!("garbage")`).
- **Write path:** `cast/3` waves a malformed `:binary_id` straight through — the
  changeset comes back `valid?: true` with the garbage in `changes` — and it only blows
  up at dump time as `Ecto.ChangeError`. Confirmed for `Upload.folder_id`
  (`Media.move_upload/2`) and `Folder.parent_id` (`Media.create_folder/1`).
  `validate_*` and `foreign_key_constraint` do **not** catch it; only an explicit
  `Ecto.UUID.cast/1` before the changeset does.

Either one kills the LiveView process (client reconnect + full page reload) instead of
returning an error the handler can flash.

**Why:** hardening here is per-function, not per-module. `Bbh.Media.get_folder/1` and
`move_folder/3` were fixed for exactly this (see ADR 0006) while their siblings on the
same call path were not, so the context has a mixed contract and it is easy to add a
handler that reaches the raising half.

**How to apply:** When reviewing any new `handle_event` whose params come from a JS hook
rather than from markup the server rendered, trace every id through to the Repo call and
ask what happens for: a non-UUID string, a valid-but-deleted UUID, a JSON number, and a
missing key. Note that a test using `Ecto.UUID.generate()` for the "bad id" case exercises
only the FK-constraint path and proves nothing about the malformed case — insist on a
literal non-UUID string. `Ecto.UUID.cast/1` before the query/changeset, or a tolerant
`get_x/1` returning `nil`, is the pattern already in the codebase. Related:
[[strict-csp-no-inline-handlers]] — the same hooks are also where CSP-safe delegated
listeners live; and [[ordering-renumber-deadlock-shape]] for the other hazard in the
same media-folder write path.
