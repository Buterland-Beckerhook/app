#!/bin/sh
# Safety dump of the stack's database before a deploy, for Komodo's "Pre Deploy".
#
#   sh ./pre-deploy-dump.sh <project> <backup-dir>
#   e.g. sh ./pre-deploy-dump.sh bbh-beta /opt/data/bbh-beta/backups
#
# A failed migration is not undone by rolling back the image, only by restoring
# the database — so take a dump before a new image can migrate. update.sh does the
# same for hand-run Prod updates (pre-update-*.dump); this is the Komodo path.
#
# - Postgres not running (first deploy, stack stopped): nothing to save, exit 0.
# - Dump fails: exit non-zero, so Komodo does not deploy.
# - Keeps the newest 5 pre-deploy-*.dump in <backup-dir>.
#
# Runs inside the Komodo Periphery container: POSIX sh, docker CLI only, and the
# backup dir must be mounted into Periphery under the same path as on the host.
# Without arguments it falls back to STACK_NAME / DATA_DIR from ./.env (manual use).
set -eu

dotenv() { [ -f .env ] && sed -n "s/^$1=//p" .env | head -n1 | sed -e 's/^"//' -e 's/"$//' || true; }

PROJECT="${1:-$(dotenv STACK_NAME)}"
PROJECT="${PROJECT:-bbh}"
if [ -n "${2:-}" ]; then
  BACKUPS="$2"
else
  DATA="$(dotenv DATA_DIR)"
  BACKUPS="${DATA:-.}/backups"
fi
KEEP=5

CID="$(docker ps -q \
  --filter "label=com.docker.compose.project=$PROJECT" \
  --filter "label=com.docker.compose.service=postgres")" || CID=""

if [ -z "$CID" ]; then
  echo "pre-deploy-dump: postgres of '$PROJECT' is not running — nothing to dump."
  exit 0
fi

# Role and database from the container itself, so .env is not needed here.
DB_USER="$(docker exec "$CID" printenv POSTGRES_USER)"
DB_NAME="$(docker exec "$CID" printenv POSTGRES_DB)"

mkdir -p "$BACKUPS"
DUMP="$BACKUPS/pre-deploy-$(date +%Y%m%d-%H%M%S).dump"
echo "pre-deploy-dump: $PROJECT/$DB_NAME -> $DUMP"

# No -t on exec: a TTY mangles the binary dump.
if ! docker exec "$CID" pg_dump -U "$DB_USER" -Fc "$DB_NAME" > "$DUMP.tmp"; then
  rm -f "$DUMP.tmp"
  echo "pre-deploy-dump: pg_dump failed — not deploying." >&2
  exit 1
fi
if [ ! -s "$DUMP.tmp" ]; then
  rm -f "$DUMP.tmp"
  echo "pre-deploy-dump: dump is empty — not deploying." >&2
  exit 1
fi
mv "$DUMP.tmp" "$DUMP"
echo "pre-deploy-dump: $(du -h "$DUMP" | cut -f1) written"

# Rotate: keep the newest $KEEP.
# shellcheck disable=SC2012
ls -1t "$BACKUPS"/pre-deploy-*.dump 2>/dev/null | tail -n +$((KEEP + 1)) | while read -r old; do
  rm -f -- "$old"
done
