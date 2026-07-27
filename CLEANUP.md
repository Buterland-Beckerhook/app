# Cleanup plan — obsolete planning documents

The Phoenix rewrite is complete and the old Directus + SvelteKit stack has been
removed. Several planning/handoff documents at the repo root pre-date the finished
rewrite and no longer describe the codebase. This plan lists what to remove and
what to keep, with rationale, so the tree stops advertising a stack that no longer
exists.

> This file is itself a temporary artifact — delete it once the cleanup below has
> been executed and reviewed.

## Recommended removals

| File | Size | Why remove |
|---|---|---|
| `RELAUNCH_PLAN.md` | ~20 KB | Describes the **old** Directus + SvelteKit + monorepo stack (`frontend/`, `migration/`, Node adapter). That stack has been removed; the plan is fully superseded by the shipped Phoenix app and by `AGENTS.md`. Nothing references it. |
| `TODO.md` | ~3 KB | Every item is checked `[x]` — the redesign task list is complete. History stays in git; a fully-done checklist at the repo root is noise. |
| `Buterland-Beckerhook homepage redesign-handoff.zip` | ~733 KB | A binary design-handoff bundle committed to git. Bloats the repo, is not consumed by any build/script, and its content (once extracted) belongs in a design store, not version control. |

```sh
git rm "RELAUNCH_PLAN.md" "TODO.md" "Buterland-Beckerhook homepage redesign-handoff.zip"
git rm "CLEANUP.md"          # this plan, once executed
```

## Keep (not stale)

| File / dir | Why keep |
|---|---|
| `Vereinsgeschichte.md` | Club-history **content + layout proposal** for the `Verein / Über uns / Vereinsgeschichte` page. Reference material for content still being entered, not a build plan. Move under `docs/` if you'd rather it not sit at the root. |
| `Webseite Konzept.md` | The navigation/IA concept the current site is built against — still a useful reference. Same note: could move under `docs/`. |
| `AGENTS.md`, `app/AGENTS.md` | Live developer/agent documentation for the current stack. |
| `docs/adr/` | Architecture decision records — the durable "why" behind current code. |
| `README.md` | Now the project's front-door doc (deploy/maintenance/usage). |

## Optional tidy-up (author's call)

- Relocate the two "keep" content docs into `docs/` (e.g. `docs/content/`) so the
  repo root holds only `README.md` + `AGENTS.md`. Purely organizational.
- If the handoff zip's contents are still needed, extract the relevant assets into
  the app (`app/priv/static/…`) or an external design store **before** removing the
  zip — do not keep the archive itself in git.
