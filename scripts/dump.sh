#!/usr/bin/env bash
# Snapshot a DB + uploaded originals into ./seed (DB dump + uploads tarball).
# The regenerable variant cache is excluded. Requires the postgres service up.
#
# Defaults target the DEV stack. Override via env to target another stack:
#   DB_NAME         database to dump          (default: bbh_dev)
#   DB_USER         connect as this role      (default: postgres)
#   UPLOADS_VOLUME  named docker volume that holds /data/uploads; when set,
#                   originals are read from the volume (prod) instead of the
#                   host bind dir app/priv/uploads (dev).
#   COMPOSE_FILE    which compose file to resolve the postgres container from
#                   (docker compose honours this env var).
#
# Dev:   make dump            (or ./scripts/dump.sh)
# Prod:  COMPOSE_FILE=deploy/compose.yml DB_NAME=bbh DB_USER=bbh \
#          UPLOADS_VOLUME=bbh-prod_uploads ./scripts/dump.sh
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SEED="$ROOT/seed"
HOST_PRIV="$ROOT/app/priv"
DB_NAME="${DB_NAME:-bbh_dev}"
DB_USER="${DB_USER:-postgres}"
UPLOADS_VOLUME="${UPLOADS_VOLUME:-}"
mkdir -p "$SEED"

# Resolve the postgres container id. We use `docker exec` (not `docker compose
# exec`, which segfaults on some Docker Desktop versions).
PG="$(docker compose ps -q postgres || true)"
if [ -z "$PG" ]; then
  echo "postgres service is not running — start it (make dev / docker compose up -d postgres)." >&2
  exit 1
fi

echo "Dumping database '$DB_NAME' (user '$DB_USER') -> $SEED/bbh.dump"
# NOTE: never add -t here — a TTY mangles the binary dump (CRLF) and pg_restore segfaults.
docker exec -i "$PG" pg_dump -U "$DB_USER" -Fc "$DB_NAME" > "$SEED/bbh.dump"

echo "Archiving uploads -> $SEED/uploads.tar.gz (variant cache excluded)"
if [ -n "$UPLOADS_VOLUME" ]; then
  docker run --rm -v "$UPLOADS_VOLUME":/data -v "$SEED":/backup alpine \
    tar czf /backup/uploads.tar.gz -C /data uploads
else
  tar czf "$SEED/uploads.tar.gz" -C "$HOST_PRIV" uploads
fi

echo "Done: $SEED/bbh.dump + $SEED/uploads.tar.gz"
