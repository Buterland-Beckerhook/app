#!/usr/bin/env bash
# Snapshot the dev DB + uploaded originals into ./seed for use as a reproducible
# seed (replaces manual seeds.exs content). The regenerable variant cache is
# excluded. Requires the postgres service up (`make dev`, or
# `docker compose up -d postgres`).
#
# Usage: make dump
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SEED="$ROOT/seed"
mkdir -p "$SEED"

# Resolve the postgres container id. We use `docker exec` (not `docker compose
# exec`, which segfaults on some Docker Desktop versions).
PG="$(docker compose ps -q postgres || true)"
if [ -z "$PG" ]; then
  echo "postgres service is not running — start it with 'make dev' or 'docker compose up -d postgres'." >&2
  exit 1
fi

echo "Dumping dev database (bbh_dev) -> $SEED/bbh.dump"
docker exec -i "$PG" pg_dump -U postgres -Fc bbh_dev > "$SEED/bbh.dump"

echo "Archiving uploads -> $SEED/uploads.tar.gz (variant cache excluded)"
tar czf "$SEED/uploads.tar.gz" -C "$ROOT/app/priv" uploads

echo "Done: $SEED/bbh.dump + $SEED/uploads.tar.gz"
