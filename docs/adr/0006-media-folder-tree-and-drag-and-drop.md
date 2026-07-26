# ADR 0006 — The media library shows its whole folder tree, and moves happen by dragging

**Status:** Accepted (2026-07-26)

## Context

Folders arrived with the media library in 2026-07-15 as a two-level tree in the
database, but the admin only ever rendered a one-level slice of it: the direct
sub-folders of wherever you stood, as a row of chips, with a breadcrumb to climb
back out. The shape existed; nobody could see it. Finding out where a picture
lived meant clicking through.

Three specific frictions came out of using it:

- **Order was not the editor's to choose.** `order_by: [asc: f.name]` was
  hard-wired at four call sites, so "Aktuelles" sorted under "Archiv 2019".
- **Filing a picture cost five interactions** — tile, "Bearbeiten", modal,
  select, save — for what is one gesture's worth of intent.
- **"Alle Medien" did not show all media.** The root scope filtered
  `is_nil(folder_id)`, so the label named the whole library while listing only
  the part of it nobody had filed. There was no view of the whole library at all.

## Decision

**The tree is always on screen and always fully expanded.** No collapse state,
no expand toggles. Two levels is the cap the schema enforces, and a collapsed
branch is somewhere a dragged file can be dropped by accident.

**"Alle Medien" now means all media**, and a separate "Ohne Ordner" node holds
the unfiled ones. The LiveView carries a `:scope` of `:all | :unfiled |
%Folder{}` where it used to carry one nullable `folder`, because that assign was
being asked to mean both "no folder chosen" and "the unfiled ones" at once.

**Folders carry an explicit `position`**, backfilled from the alphabetical order
they had, so nothing moved on deploy. Reordering renumbers the whole level from
0 rather than swapping two values — the same write path page blocks and gallery
images already used, now extracted to `Bbh.Ordering` rather than copied a third
time.

**Drag & drop is hand-written against the HTML5 API.** The app has no
`package.json`; esbuild bundles straight out of `assets/js` and third-party code
is vendored by hand into `assets/vendor/`. Two drop gestures did not justify
vendoring a sorting library, and the geometry that is actually a decision —
which third of a row the pointer is in — is one pure function
(`assets/js/tree_dnd.js`), unit-tested with `node --test`.

## Consequences

- **Touch devices get no drag & drop**, because HTML5 DnD has none. The folder
  select in the edit modal stays as the way to file a picture there, which is
  also why it was not removed once dragging existed.
- **Keyboard users get the gestures as `Alt`+arrows** (up/down to reorder,
  right/left to nest and unnest). This is not decoration: after this change the
  tree is the *only* place folder order is created, so a drag-only tree would
  have made that order unreachable without a mouse. The keys push the same two
  events the drops do, so there is one server path, not two.
- **The markup is a nested `<ul>` of links, not `role="tree"`.** The ARIA tree
  pattern promises roving-tabindex arrow-key navigation *between* items; what
  this offers is ordinary tab-navigable links plus `Alt`+arrows for *moving*
  them. Claiming the role without honouring its interaction contract would
  announce a widget to a screen reader that then does not behave like one —
  worse than the plain nesting, which already conveys the hierarchy. If full
  tree semantics are wanted later, the roving tabindex has to come with them.
- **No inline `on*` handlers.** Production CSP is `script-src 'nonce-…'
  'strict-dynamic'` with no `'unsafe-inline'` (ADR-adjacent: `BbhWeb.Plugs.CSP`),
  so an `ondragover=` would be a silent no-op in production while passing dev.
  Both hooks delegate from a container that survives LiveView patches — binding
  per row would break on the first move, and per tile on the first stream update.
  `test/bbh_web/plugs/csp_test.exs` now pins the policy that makes this
  necessary; it did not exist before, so the constraint was load-bearing and
  untested.
- **Counts on a node are of direct contents**, not the subtree. A parent whose
  pictures all live in its sub-folders reads 0. That is deliberate — the number
  says what the node will list when clicked — but it does read oddly at first,
  and it stops being literally true while a search is active: the grid filters,
  `list_folder_tree/0` does not. Left as is because a search already spans every
  folder on purpose (ADR 0004), so the counts stay the answer to "what is in
  here" while the grid answers "what matched".
- **The two-level cap now has three ways to be violated instead of one.**
  Creating under a sub-folder was the only route before; dragging adds "a folder
  with children becomes a child" and "a folder is dropped on itself".
  `Folder.move_changeset/4` refuses all three. The client mirrors the
  children-of-its-own rule — a folder with sub-folders is refused as a target on
  any row outside its own level, not merely denied the "drop inside" third, since
  dropping *between* two sub-folders also means taking their parent. So an
  impossible nest is never offered rather than flashed as an error afterwards.
  The server stays the authority either way: the ids come from the browser.
- **Re-parenting introduced a race that creation alone never had**, and both
  writers take a row lock because of it. Before this change a folder's depth was
  fixed at insert; now `create_folder/1` can add a child to folder X while
  `move_folder/3` is turning X into a sub-folder, and the two checks would each
  pass against the state before the other committed. The result is a folder on a
  third level — which is not merely untidy: neither `list_folder_tree/0` nor
  `folder_options/0` walks that deep, so the folder disappears from the tree
  *and* from the editor's select, stranding the media inside it.

  Both writers therefore take **one transaction-scoped advisory lock over the
  whole tree** (`pg_advisory_xact_lock`). Row locks on the pair {moved folder, new
  parent} were tried first and are **not** sufficient, even taken in sorted id
  order: `renumber_level/3` rewrites every sibling's position, taking a row lock
  on each in list order, and two concurrent moves build different lists — so they
  reach the same rows in opposite orders and Postgres kills one with a deadlock
  (40P01). That surfaces as a *raise*, not an `{:error, _}`, so it takes the
  LiveView down rather than flashing. Measured, not theorised: a probe of 40
  concurrent opposing reorders raised `Postgrex.Error` with the lock removed and
  none with it in place. Locking the whole tree is cheap here — a handful of rows,
  edited at human pace — and it also covers the top-level create, which has no
  parent row to lock and was otherwise unguarded against two creates racing on
  `max(position)`.

  There is no automated regression test. Under `Sandbox.mode(:shared)` every
  process shares one connection, where the deadlock cannot form; a real test needs
  per-process `Sandbox.checkout/2` and a deliberate interleaving, which the suite
  is not set up for.
- **Ids from a drop payload are a new trust level, and Ecto does not guard it.**
  `phx-value-id` on a server-rendered button can only carry an id the server just
  wrote; `pushEvent` carries whatever the page sends. Ecto is unhelpful in exactly
  this spot: `cast/3` waves a malformed `:binary_id` straight through, and the
  failure lands as an `Ecto.ChangeError` in `Repo.update` — an exception, so a
  crashed LiveView and a full page reload rather than an error the UI can show.
  Three places were hardened: `get_folder/1` (a non-UUID is now a miss falling
  back to "Alle Medien", including for a hand-typed `?folder=`),
  `Media.move_folder/3` (validated up front, returning a changeset error), and
  `Upload.changeset/2` + `update_changeset/2`, where the check sits on the
  *schema* because `folder_id` arrives both from a drop and from the editor's
  form post. `list_subfolders/1` and `next_folder_position/1` went the same way,
  so the module no longer has a mixed contract.
- The `position` column deliberately has **no unique index**. The renumber writes
  row by row, so two rows briefly share a value inside the transaction — the same
  constraint that already applied to `page_blocks.position` and
  `block_gallery_files.sort`, now documented once on `Bbh.Ordering.renumber/2`
  instead of in a comment next to one of its three users.
