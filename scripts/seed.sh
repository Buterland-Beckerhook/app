#!/usr/bin/env bash
# Restore the dev DB + uploaded originals from ./seed (produced by scripts/dump.sh).
# Recreates bbh_dev from scratch and unpacks the uploads; the variant cache is
# wiped so WebP variants regenerate on demand. Requires the postgres service up
# (`make dev`, or `docker compose up -d postgres`).
#
# Usage: make seed
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SEED="$ROOT/seed"

if [ ! -f "$SEED/bbh.dump" ]; then
  echo "Missing $SEED/bbh.dump — run 'make dump' (or copy a snapshot into ./seed) first." >&2
  exit 1
fi

# Resolve the postgres container id. We use `docker exec` (not `docker compose
# exec`, which segfaults on some Docker Desktop versions).
PG="$(docker compose ps -q postgres || true)"
if [ -z "$PG" ]; then
  echo "postgres service is not running — start it with 'make dev' or 'docker compose up -d postgres'." >&2
  exit 1
fi

echo "Recreating dev database (bbh_dev) and restoring $SEED/bbh.dump"
# --force terminates existing connections (e.g. the Phoenix pool) before dropping.
docker exec -i "$PG" dropdb -U postgres --if-exists --force bbh_dev
docker exec -i "$PG" createdb -U postgres bbh_dev
docker exec -i "$PG" pg_restore -U postgres -d bbh_dev --no-owner < "$SEED/bbh.dump"

if [ -f "$SEED/uploads.tar.gz" ]; then
  echo "Restoring uploads from $SEED/uploads.tar.gz"
  rm -rf "$ROOT/app/priv/uploads"
  tar xzf "$SEED/uploads.tar.gz" -C "$ROOT/app/priv"
  # Drop stale variants; they regenerate on first request.
  rm -rf "${ROOT:?}/app/priv/uploads_cache"/*
fi

echo "Done: dev DB + uploads restored from $SEED"
