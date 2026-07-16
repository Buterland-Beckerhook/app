# Code Review: assign_async migration (dashboard_live.ex, article_live/form.ex, user_live/index.ex)

## Summary
- **Status**: ✅ Approved
- **Issues Found**: 0 critical/warning, 2 suggestions

Verified against `deps/phoenix_live_view/lib/phoenix_live_view/async.ex` and `async_result.ex`
(LiveView installed via mix.lock, source read directly — not guessed).

Key mechanics confirmed:
- `run_async_task/5` only spawns the Task when `Phoenix.LiveView.connected?(socket)` is true;
  on the disconnected/dead mount `assign_async` still sets the assign to `AsyncResult.loading()`
  before returning, so `@stats`/`@media_library` always exist as a struct — no `KeyError` risk
  in dead render, confirmed for both dashboard_live.ex:9 and form.ex:30.
- `<.async_result>` (`phoenix_component.ex:3524`) branches on `ok? > loading > failed`, all three
  states are always present on the struct, so no missing-slot crash.
- Re-invoking `assign_async` on the same key (form.ex:58, `search_media`) is safe: each call
  stores a fresh monitor `ref` in private async state (`async.ex:279`); `prune_current_async`
  drops any result whose `ref` no longer matches the currently-stored one, so a stale keystroke's
  DB result can never clobber a newer one. Because `AsyncResult.ok?` stays `true` once set, the
  previous media list keeps rendering (no flicker to the loading slot) while the new search runs
  in the background — expected/idiomatic behavior, not a bug.
- form.ex :new action correctly omits `media_library`; every `@media_library` reference in the
  template is inside the `<section :if={@live_action == :edit}>` block (form.ex:217, :267), and no
  `handle_event`/`handle_async` clause reads `@media_library` outside that guarded render path.
  Even if a client fired `"search_media"` while `live_action == :new`, `assign_async` handles a
  previously-unassigned key gracefully (no crash) — the assign would just be set and remain
  unrendered.
- user_live/index.ex: `id={"role-#{u.id}"}` on the per-row `set_role` form is correct and needed
  to keep LiveView's DOM diffing/patching stable across list re-renders after `load_users/1`.

## Suggestions
1. **form.ex:58-60** (`search_media`): each debounced keystroke starts a brand-new DB query even
   though the previous task's result is later discarded by ref-mismatch — the old task is not
   explicitly cancelled, so superseded searches still run to completion against the DB. Harmless
   at current scale; consider debounce tuning or `Task` cancellation only if `list_uploads/1`
   becomes expensive.
2. **dashboard_live.ex:13-23** (`load_stats/0`): the four counts run sequentially inside one task.
   Fine for simplicity/current load; if this becomes a bottleneck, four independent
   `Task.async/await_many` calls (or four separate `assign_async` keys) would parallelize them.
