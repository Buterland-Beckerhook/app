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

## Media pipeline

Originals live under `:uploads_dir` keyed by `storage_key`; responsive WebP variants
are generated on demand into `:media_cache_dir`, **one directory per upload**
(`<cache>/<sha256(storage_key)>/<sha256(size…)>.webp`). That grouping is what lets
`Bbh.Media.purge_variants/1` drop an upload's variants as a unit — their file names are
content hashes, so there is no other way to find them all. The cache is regenerable and
excluded from backups, so it can be deleted wholesale at any time.

Image **metadata has exactly one home**: the media library (`/admin/medien`, or the same
modal opened from the article form). Titel, Bildunterschrift, Beschreibung (Alt-Text) and
Copyright are fields on `media`; an embedding (article image, gallery file) only records
*how* the picture is used. Templates read them through `BbhWeb.Format.image_alt/1`,
`image_caption/1` and `image_copyright/1` — never off the embedding. See
`docs/adr/0004-media-library-owns-image-metadata.md`.

**Rotation** (`Bbh.Media.rotate_upload/2`) rewrites the original in place and bumps
`media.revision`, which busts three caches: the browser's (it rides on media URLs as
`?v=`), the variant cache on disk (it joins the cache key, so a stale file is unreachable
and not merely deleted), and the libvips operation cache — libvips memoizes by file name
and would otherwise keep serving the old orientation from memory.

## E-mail addresses

Addresses are stored in the clear and obfuscated **at render time** — never write one
into a public template as plain text or a `mailto:` link. `BbhWeb.Format.render_richtext/1`
pipes the finished HTML through `BbhWeb.EmailObfuscation.rewrite/1`, which covers
editor-authored `mailto:` links, addresses typed into the copy, and resolved
`{{ role.email }}` placeholders. For an address set in a template use the
`<.email_link address={...} />` component. The address is split into chunks with hidden
decoy fragments between them, so it stays readable and copyable **without** JavaScript;
`assets/js/mail.js` upgrades the anchor to a real `mailto:` on first interaction. See
`docs/adr/0005-email-obfuscation.md`.

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
  UPLOADS_VOLUME=bbh-prod_uploads ./scripts/seed.sh

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

## BLZ table (IBAN → BIC/Kreditinstitut)

The membership form derives BIC/Kreditinstitut from a German IBAN via a stripped
Deutsche Bundesbank "Bankleitzahlendatei" (`Bbh.Blz`, loaded into `:persistent_term`
at boot). Everything degrades gracefully — an unknown/outdated BLZ just leaves the
fields blank.

- Committed data: `app/priv/data/blz.tsv` (`BLZ<TAB>BIC<TAB>Name`, ~3.5k rows).
- Refresh (~quarterly, the download URL is not stable so it's manual): download the
  new `blz-aktuell-csv-data.csv` from bundesbank.de, then
  `mix bbh.blz.strip path/to/blz-aktuell-csv-data.csv` and commit the regenerated TSV.
- Override without a rebuild: drop a newer `blz.tsv` at `/data/blz.tsv` in the uploads
  volume (or set `BLZ_DATA_FILE`); it wins over the shipped copy on next boot.

## Git & Workflow

- Default branch: `main`. Feature branches off it (e.g. `feat/…`).
- Conventional commit messages — `feat:`, `fix:`, `chore:`, `docs:`, `refactor:`.
- The site is German-language; UI strings and `de-DE` date formatting are
  hardcoded.

## Continuous Integration & dependency security

Two GitHub Actions workflows (`.github/workflows/`):

- **`ci.yml`** — test + audit gate on every PR and push. Runs `mix format
  --check`, `compile --warnings-as-errors`, `deps.unlock --check-unused`, the
  security audits (`mix deps.audit` for dependency CVEs via `mix_audit`, `mix
  hex.audit` for retired packages, `mix sobelow --config` for Phoenix SAST), and
  `mix test` against a Postgres service. This is the required check that gates
  Renovate's auto-merge.
- **`build.yml`** — builds the Phoenix release image and pushes it to GHCR (see
  the deploy notes). Actions are pinned to commit SHAs; Renovate keeps them current.

**Renovate** (`renovate.json`) opens dependency-update PRs weekly (Elixir/mix,
GitHub Actions, Docker base images, docker-compose). Patch/minor/digest updates
auto-merge once `ci.yml` is green; majors wait for manual review. The
Elixir/OTP/Debian versions in the Dockerfiles and `ci.yml` are updated via a
custom manager driven by `# renovate:` annotation comments — keep those comments
directly above the version line if you move them. Config is read from the default
branch, so a bootstrap `renovate.json` on `main` points Renovate at the active
branch until the rewrite merges.

**Sobelow** false positives are suppressed with inline `# sobelow_skip [...]`
annotations (with a justifying comment) at the specific call site, or via
`app/.sobelow-conf` for router-level checks — never with a blanket disable. Run
locally with `mix sobelow --config` (included in `mix precommit`).
