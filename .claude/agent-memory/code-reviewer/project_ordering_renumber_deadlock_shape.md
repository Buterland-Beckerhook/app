---
name: ordering-renumber-deadlock-shape
description: Bbh.Ordering.renumber/2 writes positions row by row in list order, so two concurrent reorders of the same level deadlock in Postgres — pairwise FOR UPDATE locks do not prevent it
metadata:
  type: project
---

`Bbh.Ordering.renumber/2` (`app/lib/bbh/ordering.ex`) rewrites a whole level 0..n-1 one
`UPDATE` at a time, inside a transaction. It backs all three hand-ordered lists in the
app: `page_blocks.position`, `block_gallery_files.sort`, `media_folders.position`.

**The hazard:** each `UPDATE` takes a row lock held to commit, and the *write order* is
the new list order — which differs between two transactions because each inserts its own
moved row at a different index. T1 ends up holding row A and waiting for row B while T2
holds B and waits for A. Postgres resolves it by killing one transaction with
`Postgrex.Error 40P01 deadlock_detected`, which is a raise, not an `{:error, _}` — so it
crashes the calling LiveView rather than flashing.

Taking a `SELECT … FOR UPDATE` on the *pair* of rows a move touches (the moved row and
its new parent), even in sorted id order, does **not** fix this: the renumber phase then
locks n more rows that were not in the ordered set, and the moved row is itself a member
of the level. Reproduced against the dev DB on `Bbh.Media.move_folder/3` — reliably for
two root-level reorders, and in ~3 of 5 runs for two reorders inside the same parent
(it depends on whether the parent's UUID happens to sort first).

**Why it matters here:** the media folder tree is the first of the three where two
editors realistically drag at the same moment, and ADR 0006 asserted the opposite
("Each takes a single row lock at a time, so they can queue but cannot deadlock").

**How to apply:** whenever a change touches `Bbh.Ordering` or adds a fourth caller, ask
what two concurrent reorders of the same list do. The boring fix is one
`pg_advisory_xact_lock(<constant>)` per ordered collection, taken first in every writer
(including the *create* path, which also reads `max(position)` unlocked); it serialises
lists that are a handful of rows and removes the lock-ordering reasoning entirely.

Testing note: the ADR claims this is untestable because the ExUnit sandbox puts every
process on one connection. That is only true under `Sandbox.mode(:shared)`; with a
per-process `Sandbox.checkout/2` each task gets its own connection and transaction, and
row locks do block — so a regression test is possible. Related:
[[liveview-hook-payload-trust]].
