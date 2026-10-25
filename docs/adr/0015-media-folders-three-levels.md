# ADR 0015 — Media folders go three levels deep, and the cap is one number

**Status:** Accepted (2026-10-25)

**Supersedes in part:** [ADR 0006](0006-media-folder-tree-and-drag-and-drop.md) and
[ADR 0007](0007-media-tree-edit-mode-and-collapsing.md) — the two-level cap both of
them build on.

## Context

The library is filed by year: „Archiv / 2026". Inside a year the pictures pile up
unsorted — Schützenfest, Königsschießen, Jahreshauptversammlung all in one grid —
and two levels leave no room for those categories.

The cap was not one rule but an assumption spread through the code: a nested
preload of exactly one level, headings and select labels of the form
"parent / name", a picker breadcrumb of at most two crumbs, branch counts and scopes
that only looked at direct children, and a drag hook that knew only "top level" and
"leaf". Raising it to three by adding one more of each would have left the next
change just as expensive.

## Decision

**Three levels, set once** as `Bbh.Media.Folder.max_depth/0`. Everything else is
written for any depth:

- **The tree is assembled in memory** from one query over `media_folders`
  (`list_root_folders/0`), not a nested preload. Counts, the folder select, branch
  scopes (`Media.branch_ids/2`) and the LiveView's tree component recurse over it.
- **A move checks the branch, not the folder.** `Folder.move_changeset/4` takes the
  target's level and the moved branch's ids and height (read under the existing tree
  lock): the deepest folder it carries must stay within the cap, and the target must
  not lie inside the branch. The old rule "a folder with sub-folders cannot be
  nested" was the two-level special case of this and is gone — „2026" with its
  categories can now be hung under „Archiv".
- **The hook does the same arithmetic.** Rows carry `data-depth` and `data-height`,
  the tree `data-max-depth`; `fits/3` in `tree_dnd.js` decides whether a drop is
  offered. The server stays the authority.
- **`get_folder/1` preloads the whole parent chain**, and `Folder.path/1` is what
  headings, the "new folder" hint and the picker breadcrumb name a folder by.

## Consequences

- Creating a folder while standing on the deepest level still creates it on the top
  level, as before on the second; the hint says so.
- Opening a deep folder unfolds every folder above it, not just its parent.
- Alt+Left lifts a folder one level, next to the folder it came out of.
- Raising the cap again is a change to `@max_depth` plus the tests that pin "3".
  Width in the tree is the real limit — each level indents the row further.
- Like ADR 0007, the drag & drop changes were not clicked through in a browser; the
  pure part (`fits/3`) is unit-tested and the server handlers are covered.
