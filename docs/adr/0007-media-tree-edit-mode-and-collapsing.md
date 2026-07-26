# ADR 0007 — Sorting the media folder tree is a mode; outside it branches fold and a folder shows its whole branch

**Status:** Accepted (2026-07-26)

**Supersedes in part:** [ADR 0006](0006-media-folder-tree-and-drag-and-drop.md) —
its "always fully expanded, no collapse state" decision and its direct-contents
count rule.

## Context

ADR 0006 put the folder tree permanently on the page, fully expanded, with a drag
grip in every row. Two of its premises do not survive contact with the library as
it fills up.

**The grip is priced as if sorting were the common act.** It is not. Order gets
arranged once when a folder is created and then left alone for months; navigating
happens every time somebody looks for a picture. So the tree spends nearly all its
life showing an affordance for the rare intent — one that is also a mis-click
surface a pixel away from the link that is the frequent intent.

**"Two levels fit on screen" is a statement about depth, not size.** Depth is
capped; width is not. The tree gains a row per archive year and a row per
sub-folder inside it, and every one of them is permanently unfolded. Past a
handful of folders the tree, not the media, is what fills the first screen of a
page whose job is showing media.

The reason ADR 0006 gave for refusing to fold — "a collapsed branch is somewhere a
dragged file can be dropped by accident" — is sound, but it is an argument about
*while dragging*, and it was applied to *always*.

One thing genuinely blocked folding, though: a folder listed only its own files.
Fold "Presse" and the pictures in "Presse / 2026" became unreachable without
unfolding it again, so the fold really would have hidden something.

## Decision

**Sorting is a mode, off by default** — a checkbox "Ordner sortieren" above the
tree. On: grips in every row, the whole tree unfolded, `Alt`+arrows live. Off:
no grips, and folders with sub-folders fold.

That gives ADR 0006 exactly what it argued for, scoped to when it is true: while a
folder *can* be dragged, nothing is folded.

**A folder lists its own files and its sub-folders' too.** This is what makes
folding lossless rather than merely tidy — with the branch closed, everything
inside it is still one click away. `Media.list_uploads(folder:)` therefore takes a
list of ids as well as a single one, and the LiveView passes
`[folder | sub-folders]` read off the tree it already loaded.

**Counts follow the listing.** ADR 0006's rule was "the number says what the node
will list when clicked", implemented as direct contents. The rule is kept and the
implementation changes: a top-level folder counts its own files plus its
sub-folders'. `list_folder_tree/0` still runs one grouped query and folds over the
preloaded children, so this costs nothing.

**Folded state lives on the server** (`expanded`, a `MapSet` in the LiveView),
not in a `<details>` element.

## Consequences

- **The fold state and the mode are assigned in `mount/3` only.** Picking a folder
  is a `live_patch`, so it runs `handle_params/3` — where `editing` and
  `new_folder` are deliberately reset. Assigning either there would drop the mode
  on every click in the tree and re-fold the branch just opened.
  `media_live_test.exs` pins this ("the mode survives picking a folder"); it is the
  kind of bug that only shows up on the second click.
- **Opening a sub-folder unfolds the branch it sits in.** Default-folded plus a
  deep link (`?folder=<sub-folder>`, a bookmark, the patch after deleting a
  folder) would otherwise select a row nobody can see. `reveal_parent/2` handles
  it, and the same function unfolds a folder's new parent after it is nested — so
  a folder dragged into a branch does not vanish when the mode goes back off.
  This reveal is also **why `expanded` is server state and `<details>` was not an
  option**: the server has to be able to open a branch. A dynamic
  `open={…}` attribute is in the diff, so every patch would force it back to
  whatever the server thought, undoing the reader's own toggling.
- **A folded branch is `hidden`, not absent.** The `<ul>` stays rendered, so the
  toggle's `aria-controls` always resolves to a real element and folding is an
  attribute patch rather than a structural one. `[hidden]` is `display: none`, so
  a folded row is not a drop target either.
- **A branch can be folded while the sub-folder inside it is the open one.** The
  selected row then goes out of sight with `aria-current` still on it, which looks
  wrong written down but is what every tree does — the reader folded it on purpose,
  the heading over the grid still names the folder, and unfolding brings the
  highlight back. Refusing to fold that one branch would be a special case nobody
  could discover.
- **A folder move now reloads the grid, not just the tree.** This is new work the
  branch scope created: before it, moving a folder could not change which files the
  open folder lists, so `move_folder` only reloaded the tree and the heading.
  Nesting a folder into the open one now pulls its files in and un-nesting takes
  them away — without the reload the count claimed the new branch while the grid
  still showed the old set, and a file that had left stayed on screen until the
  next navigation. Both directions are pinned by tests.
- **`Alt`+arrows are refused outside the mode, and not for symmetry.** Folded rows
  are `hidden` but still in the DOM, and the hook's `siblings()` counts every row
  on a level — a position worked out against a half-invisible level is not the one
  the editor is looking at. Drags need no such check: `start()` begins at
  `[data-drag-handle]`, and the grip only exists in the mode.
- **Filing a tile by dragging it onto a folder still works in both modes.** It
  never touches a grip, and it is the gesture ADR 0006 was built for. Dropping
  onto a folded folder files into that folder, which is what its label says; the
  branch below it is not a target it could be confused with, because
  `display: none` rows take no pointer events.
- **The keyboard help text is only rendered in the mode**, and `aria-describedby`
  on the `<nav>` with it, so the reference never dangles at an id that is not
  there.
- **The media picker keeps exact folder filtering.** `media_picker.ex` navigates
  *into* sub-folders with chips and a breadcrumb; there, showing a sub-folder's
  files at the parent would duplicate everything the next click leads to. Two
  surfaces, two rules — the library browses a branch, the picker walks a path.
- **`tree.counts` no longer holds the `nil` bucket** and now has an entry for every
  folder, including empty ones. `tree.unfiled` was already the unfiled count and
  stays the only way to ask for it; `tree.total` is still summed from the *direct*
  counts, because summing the branch counts would count every parent twice.
- **`in_scope?/2` had to learn the branch as well.** Filing a tile into a
  sub-folder of the open folder keeps it in the grid — the scope still lists it, so
  removing it from the stream would read as a delete. It now takes the socket and
  mirrors `folder_scope/2` off one shared `branch_ids/2`, rather than restating the
  rule.
- **Not verified in a browser.** No browser runs in this environment (ARM64, no
  Chrome-for-Testing build, no `chromium` package), so nobody has clicked a fold
  toggle or held `Alt`. What is covered: the rendered contract the hook depends on
  (`data-edit-mode`, the presence and absence of `[data-drag-handle]`, the `hidden`
  attribute, `aria-expanded`/`aria-controls`) and every server handler. The
  one-line mode check in `key()` is DOM plumbing with no decision in it, so it was
  not pulled into `tree_dnd.js` — the pure geometry there is untouched by this
  change.
