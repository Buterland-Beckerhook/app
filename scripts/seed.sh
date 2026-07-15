#!/usr/bin/env bash
# Restore a DB + uploaded originals from ./seed (produced by scripts/dump.sh).
# Recreates the target DB from scratch and unpacks the uploads; the variant
# cache is wiped so WebP variants regenerate on demand. Requires postgres up.
#
# The dump is restored with --no-owner --no-privileges, so it is role-agnostic:
# the same artifact seeds dev and prod regardless of the source DB name/owner.
#
# Defaults target the DEV stack. Override via env to target another stack:
#   DB_NAME         database to (re)create + restore into  (default: bbh_dev)
#   DB_USER         connect as this role                   (default: postgres)
#   UPLOADS_VOLUME  named docker volume that holds /data/uploads; when set,
#                   originals are written to the volume (prod) instead of the
#                   host bind dir app/priv/uploads (dev).
#   COMPOSE_FILE    which compose file to resolve the postgres container from.
#
# Dev:   make seed            (or ./scripts/seed.sh)
# Prod:  COMPOSE_FILE=deploy/compose.yml DB_NAME=bbh DB_USER=bbh \
#          UPLOADS_VOLUME=bbh_uploads ./scripts/seed.sh
#          (stop the phoenix service first — this drops & recreates the DB)
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SEED="$ROOT/seed"
HOST_PRIV="$ROOT/app/priv"
DB_NAME="${DB_NAME:-bbh_dev}"
DB_USER="${DB_USER:-postgres}"
UPLOADS_VOLUME="${UPLOADS_VOLUME:-}"

if [ ! -f "$SEED/bbh.dump" ]; then
  echo "Missing $SEED/bbh.dump — run 'make dump' (or copy a snapshot into ./seed) first." >&2
  exit 1
fi

# Resolve the postgres container id. We use `docker exec` (not `docker compose
# exec`, which segfaults on some Docker Desktop versions).
PG="$(docker compose ps -q postgres || true)"
if [ -z "$PG" ]; then
  echo "postgres service is not running — start it (make dev / docker compose up -d postgres)." >&2
  exit 1
fi

echo "Recreating database '$DB_NAME' (user '$DB_USER') and restoring $SEED/bbh.dump"
# --force terminates existing connections (e.g. the Phoenix pool) before dropping.
docker exec "$PG" dropdb -U "$DB_USER" --if-exists --force "$DB_NAME"
docker exec "$PG" createdb -U "$DB_USER" "$DB_NAME"
docker exec -i "$PG" pg_restore -U "$DB_USER" -d "$DB_NAME" --no-owner --no-privileges < "$SEED/bbh.dump"

if [ -f "$SEED/uploads.tar.gz" ]; then
  echo "Restoring uploads from $SEED/uploads.tar.gz"
  if [ -n "$UPLOADS_VOLUME" ]; then
    docker run --rm -v "$UPLOADS_VOLUME":/data -v "$SEED":/backup alpine \
      sh -c 'rm -rf /data/uploads && tar xzf /backup/uploads.tar.gz -C /data && rm -rf /data/uploads_cache/*'
  else
    rm -rf "$HOST_PRIV/uploads"
    tar xzf "$SEED/uploads.tar.gz" -C "$HOST_PRIV"
    # Drop stale variants; they regenerate on first request.
    rm -rf "${HOST_PRIV:?}/uploads_cache"/*
  fi
fi

echo "Done: database '$DB_NAME' + uploads restored from $SEED"
