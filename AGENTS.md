# AGENTS.md

## Project Overview

Repository for **buterland-beckerhook.de** — a German shooting club
(Schützenverein) website. The site is an **Elixir + Phoenix** application: the
public site is server-rendered HEEx, the admin area is Phoenix LiveView, data
lives in PostgreSQL, and uploaded media is stored on a local volume with
libvips-generated responsive WebP variants. Deployed via Docker Compose behind a
Caddy reverse proxy.

> The site was rewritten from an earlier Directus CMS + SvelteKit stack; that
> stack has been removed. All application code now lives under `app/`.

## Repository Structure

```
app/          # The Phoenix application (OTP app :bbh) — see app/AGENTS.md
  lib/        # Contexts (Bbh.*) + web layer (BbhWeb.*: controllers, live, components)
  config/     # config.exs, dev.exs, runtime.exs (prod env), test.exs
  priv/       # repo/ (migrations, seeds.exs), static/, uploads/ (gitignored media)
  test/       # ExUnit tests + support/ fixtures
  Dockerfile      # Production release image (multi-stage mix release)
  Dockerfile.dev  # Development image (single-stage mix, source mounted)
deploy/       # Production stack: compose.yml, Caddyfile, backup.sh, .env.example
scripts/      # dump.sh / seed.sh — DB + uploads snapshot/restore (dev & prod)
docs/adr/     # Architecture decision records
compose.yml   # Development stack: postgres + phoenix + caddy
Makefile      # Dev workflow shortcuts (below)
```

## Development

Dev runs **fully containerized** (`compose.yml`): PostgreSQL + Phoenix (source
bind-mounted with code reload) + Caddy (local HTTPS at `https://localhost`).
Use the repo-root `Makefile`:

```bash
make dev        # Start the dev stack at https://localhost (docker compose up --build)
make down       # Stop the stack (data persists in volumes)
make logs       # Tail the running stack

# The following exec `mix` inside the running phoenix container (stack must be up):
make test       # mix test
make format     # mix format
make precommit  # compile --warnings-as-errors + deps.unlock --unused + format + test
make migrate    # mix ecto.migrate
make reset-db   # mix ecto.reset
```

For a clean HTTPS padlock, trust Caddy's local CA once: extract
`/data/caddy/pki/authorities/local/root.crt` from the `caddy_data` volume and add
it to your system trust store. Everything works over HTTPS regardless.

Elixir/Phoenix conventions (contexts, LiveView, Ecto, HEEx, testing) are
documented in **`app/AGENTS.md`**.

## Data snapshots — seeding & restore

There is no hand-written sample seed; dev data is a **real snapshot**.
`scripts/dump.sh` / `scripts/seed.sh` capture and restore a PostgreSQL dump
(`pg_dump -Fc`) plus a tarball of the uploaded originals (the regenerable variant
cache is excluded) into a gitignored `./seed` directory. `priv/repo/seeds.exs` is
only a dev-admin fallback for an otherwise empty database.

```bash
make dump   # Snapshot dev DB + uploads  -> ./seed/{bbh.dump,uploads.tar.gz}
make seed   # Restore ./seed snapshot into the dev DB + uploads
```

The scripts are **role- and name-agnostic** (restore uses
`--no-owner --no-privileges`), so the same artifacts seed dev *and* prod. Override
via env vars — all default to the dev values:

| Var | Default | Purpose |
| --- | --- | --- |
| `DB_NAME` | `bbh_dev` | Database to dump / (re)create + restore into |
| `DB_USER` | `postgres` | Role to connect as |
| `UPLOADS_VOLUME` | *(unset)* | Named Docker volume holding `/data/uploads` (prod); unset ⇒ the `app/priv/uploads` host bind dir (dev) |
| `COMPOSE_FILE` | `compose.yml` | Which stack's `postgres` container to target |

**Restore a dev snapshot into the prod stack** (from repo root):

```bash
# Stop the phoenix service first — this drops & recreates the DB.
docker compose -f deploy/compose.yml stop phoenix

COMPOSE_FILE=deploy/compose.yml DB_NAME=bbh DB_USER=bbh \
  UPLOADS_VOLUME=bbh_uploads ./scripts/seed.sh

docker compose -f deploy/compose.yml up -d phoenix   # variants regenerate on demand
```

Notes:
- The dump carries the full schema + `schema_migrations`, so restore into an
  **empty** target DB (running `bin/migrate` afterwards is a harmless no-op since
  the versions match).
- The scripts resolve the container via `docker compose ps -q postgres` and use
  `docker exec` (not `docker compose exec`, which segfaults on some Docker
  versions). **Never** create a dump with `docker exec -t` — a TTY corrupts the
  binary stream and `pg_restore` then segfaults.
- Nightly production backups (dump + uploads, offsite via Borg) are handled
  separately by `deploy/backup.sh`.

## Git & Workflow

- Default branch: `main`. Feature branches off it (e.g. `feat/…`).
- Conventional commit messages — `feat:`, `fix:`, `chore:`, `docs:`, `refactor:`.
- The site is German-language; UI strings and `de-DE` date formatting are
  hardcoded.
