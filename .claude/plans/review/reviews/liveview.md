# LiveView Review — feat/phoenix-rewrite

Scope: admin LiveViews, user_live/*, core_components.ex, layouts.ex, site_components.ex.
All files are NEW (initial Phoenix rewrite) — no pre-existing baggage to grandfather in.

## Findings

### Streams vs assigns

- `article_live/index.ex:8,18`, `event_live/index.ex:8,16`, `location_live/index.ex:8,16`,
  `page_live/index.ex:8,16`, `person_live/index.ex:9,17`, `admin/user_live/index.ex:16,53`,
  `media_live/index.ex:11,52-58` — **SUGGESTION** — all six admin index LiveViews load full
  lists via `assign(:x, Repo.list_x())` instead of `stream/3`, and re-run the full query +
  re-assign the whole list on every mutation (delete/invite/filter). Why: `core_components.ex:406`
  already special-cases `Phoenix.LiveView.LiveStream` in `<.table>`, so the component is
  stream-ready but unused — this looks like an intentional half-migration. Given this is a small
  club-site admin (articles/events/people/pages numbering in the dozens-hundreds, not thousands),
  the O(n) memory cost is low risk today, but `media_live/index.ex` (image library) is the one
  most likely to grow past hundreds of items over time. Fix: convert `media_live` (and ideally
  all six) to `stream(socket, :items, ...)` + `stream_insert`/`stream_delete` on mutation instead
  of full reload, and switch `<.table rows={@streams.x}>` per component's existing stream branch.
  Not a blocker given current data scale, but flag now before dataset grows.

### Mount / handle_params discipline

- All admin `*_live/index.ex` and `*_live/form.ex` — **one-liner (acceptable for this scale)** —
  DB queries run unconditionally in `mount/3` (no `assign_async`, no `connected?` guard). This is
  the Iron Law #1 default violation, but these are auth-gated internal admin pages (not
  SEO-critical, not public), so the double-mount cost is two small queries against a tiny admin
  dataset — low practical impact. Still, `dashboard_live.ex:6-11` runs 4 separate queries
  (1 custom + 3 raw `Repo.aggregate`) synchronously in mount on every connect; consider
  `assign_async` there since it's pure display data with no dependency on the rest of mount.
- `article_live/form.ex:23-36` (`apply_action/3` for `:edit`) — **SUGGESTION** — loads article,
  images, and full media library (`Bbh.Media.list_uploads()`) all synchronously in mount/apply_action.
  The media picker list is unrelated to the primary article data and a good `assign_async`
  candidate, especially once the media library grows.
- No LiveView here uses `handle_params/3` at all — all data loading happens in `mount` via
  `apply_action`, which is actually correct per Iron Law #4 for pages with no independent
  pagination/filter URL state (none of these routes carry query params for paging).

### PubSub / real-time

- No `subscribe`/`Phoenix.PubSub` calls anywhere in the reviewed LiveViews — no `connected?` gating
  issue exists because there are no subscriptions. `article_live/form.ex:150` and
  `event_live/form.ex:92` use `Task.start(fn -> Bbh.Notifications.notify(...) end)` for one-shot
  push notifications, which is fire-and-forget and unsupervised — **SUGGESTION** — an
  unsupervised `Task.start` will silently swallow crashes with no visibility (no Task.Supervisor,
  no telemetry). Consider `Task.Supervisor.start_child/2` under the app's supervision tree instead
  of raw `Task.start/1` for resilience/observability, not a correctness bug today.

### handle_event / handle_info correctness

- `article_live/form.ex:100-107` `reload_article/1` — **SUGGESTION** — re-fetches the article,
  images, and rebuilds the throne form after every throne save/delete; correct but re-queries
  4 things where 1-2 targeted updates would do (fine at this scale).
- `page_live/form.ex:102-104` `find_pb/2` uses `Enum.find_value` returning `pb.id == pb_id && pb`,
  comparing an Ecto struct id against the string `pb_id` from `phx-value-pb_id` (used by
  `move`/`delete_block`/`save_block` handlers at lines 51/63/68) — **verified not a bug**:
  `Bbh.Schema` (`app/lib/bbh/schema.ex:11`) sets `@primary_key {:id, :binary_id, autogenerate: true}`
  project-wide, so `pb.id` is already a UUID string and the comparison is safe.
- `admin/user_live/index.ex:39-42` `set_role` compares `id == socket.assigns.current_scope.user.id`
  in the `delete` handler (line 45) but not in `set_role` — **SUGGESTION** — an admin could
  demote/change their own role via the row select with no self-protection guard, unlike delete
  which explicitly protects against self-deletion. Low severity (role change is reversible by
  another admin) but inconsistent with the delete guard's intent.

### Form component structure

- All admin forms use `to_form(changeset, as: "x")` + `<.form phx-change="validate" phx-submit="save">`
  correctly, and all `save`/`update_*` branches in Settings/Totp/Article/Event/Location/Person
  correctly pattern-match `{:error, changeset}` / `{:error, %Ecto.Changeset{}}` explicitly rather
  than a bare `{:error, _}` — no silent-form-save risk found (Iron Law #10 respected).
- `article_live/form.ex:226-247` nested per-image `<.form>` inside the parent form's `:for`
  loop, and `page_live/form.ex:184-188` nested per-block `<.form>` inside `:for` — correct
  pattern (separate form scope per row, unique DOM ids `image-#{img.id}` / `block-#{pb.id}`) —
  no issue.
- `media_live/index.ex:69` outer `<form phx-submit="save" phx-change="validate">` for uploads —
  correct use of plain `form` (no changeset) is fine for uploads.

### LiveComponent vs function component

- No `LiveComponent` used anywhere in this diff — every reusable UI piece
  (`stat_card`, `block_fields`, `.table`, `.input`, `.rich_text`) is a function component. This
  matches official guidance ("prefer function components") — **no issue**, good default.

### Navigation (live_patch/navigate vs push_navigate)

- Correct and consistent use of `navigate={~p"..."}` for cross-LiveView links and
  `push_navigate(to: ...)` after save/delete across all admin forms — no `live_patch`/`push_patch`
  needed since none of these routes carry URL-driven pagination/filter state. No issue.
- `settings.ex:83` `push_navigate` after email-confirmation mount — correct (avoids re-render
  with stale token param).

### N+1 (one-liner, Ecto agent owns depth)

- `event_live/index.ex:33` accesses `e.location.name` per row inside `<.table>` — verify
  `Calendar.list_events()` preloads `:location` (Ecto agent to confirm); if not preloaded, N+1
  per row.

## Summary

No BLOCKERs. Confirmed `page_live/form.ex` `find_pb/2` id comparison is safe (binary_id PKs
project-wide). All admin index views use assigns instead of the stream-ready `<.table>`
component — SUGGESTION to migrate, especially `media_live`. No PubSub/connected? issues (none
present). No LiveComponent misuse. Form/changeset error handling is correct throughout.
