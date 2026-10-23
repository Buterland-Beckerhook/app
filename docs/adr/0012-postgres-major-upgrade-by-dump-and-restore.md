# ADR 0012 — Postgres majors move by dump & restore into a new volume

**Status:** Accepted (2026-10-23)

## Context

Beta and Prod went live on `postgres:16-alpine`. Moving to 18 is not a tag bump:

- A Postgres server only opens data directories of its own major version. The data has
  to be converted, either with `pg_upgrade` (needs the binaries of **both** majors in one
  place) or by dumping from the old server and restoring into the new one.
- The official 18+ images changed their layout: `PGDATA` is now
  `/var/lib/postgresql/18/docker` and the declared volume is `/var/lib/postgresql`,
  matching `pg_ctlcluster`. Their entrypoint refuses to start when it finds an old
  cluster where it expects its own. Our mounts at `/var/lib/postgresql/data` had to change
  anyway.
- `initdb` in 18 enables data checksums by default; `pg_upgrade` requires old and new
  clusters to agree, so a 16 cluster without checksums would need the new one created
  with `--no-data-checksums`.
- The database is small (a club website: articles, events, media metadata). A dump
  takes seconds, and short downtime is acceptable.
- The deploy stack already has the restore machinery: `backup.sh` writes `pg_dump -Fc`
  archives and the `restore` service loads a queued `*.dump` before Phoenix boots.

## Decision

**Dump & restore into a new named volume** (`${STACK_NAME}_pgdata`, mounted at
`/var/lib/postgresql`). `deploy/upgrade-postgres.sh` does it in one step per stack:
dump from a throwaway old-major container on the legacy volume, restore through the
existing `restore` service, verify per-table row counts, start the stack.

- **The legacy volume is never written.** It stays in place as the rollback: point the
  old `compose.yml` at it and the old server comes back with the data as of the upgrade.
- **New clusters get 18's defaults** (checksums on) rather than inheriting 16's.
- **A tripwire, not a convention, guards the order of operations.** The `restore` service
  mounts the legacy volume read-only. If it holds a cluster while the new database is
  empty and no dump is queued, `restore` exits non-zero, so Phoenix (which depends on it)
  never starts, migrates and serves an empty site. That is exactly the state after an
  `update.sh` run without the upgrade script.
- **Beta before Prod.** Archives are readable by the same or newer `pg_restore` only, so
  `sync-data.sh` (Prod → Beta) keeps working only while Beta is ahead.

`pg_upgrade --link` was rejected: it needs a combined image (or both binaries mounted
together), the checksum mismatch handled by hand, and it rewrites the old cluster's
state, which would cost the zero-effort rollback. Its speed advantage is irrelevant at
this size.

## Consequences

- One manual step per stack, documented in `deploy/README.md` ("Postgres major upgrade").
- The legacy volume lingers until someone removes it; it costs only disk space.
- The script and the tripwire are specific to the 16 → 18 move (the legacy volume name
  is fixed). From 18 on, the data already lives in a major-version subdirectory, and a
  future 19 image refuses to start on an 18 cluster instead of silently initialising a new
  one. The next major upgrade needs its own plan; Renovate's major-bump PR for Postgres
  carries a note saying so.
