#!/usr/bin/env bash
# Nightly backup: Postgres dump + uploads, staged locally then pushed offsite via Borg.
# Cron (root):  0 3 * * *  /path/to/deploy/backup.sh >> /var/log/bbh-backup.log 2>&1
#
# Requires: DB_USER (env), BORG_REPO + BORG_PASSPHRASE (env) for the offsite Borg repo.
set -euo pipefail

STAMP="$(date +%F)"
STAGING="/var/backups/bbh"
COMPOSE_DIR="$(cd "$(dirname "$0")" && pwd)"

# Compose project name = named-volume prefix. Prefer an explicit env override,
# else read it from .env (written by setup.sh), else the legacy default.
STACK_NAME="${STACK_NAME:-$(sed -n 's/^STACK_NAME=//p' "$COMPOSE_DIR/.env" 2>/dev/null | head -n1)}"
STACK_NAME="${STACK_NAME:-bbh}"

mkdir -p "$STAGING"

# 1. Postgres (custom format, restorable with pg_restore). Pass --env-file so the
#    compose project name (name: ${STACK_NAME}) resolves regardless of cron's cwd.
docker compose --env-file "$COMPOSE_DIR/.env" -f "$COMPOSE_DIR/compose.yml" exec -T postgres \
  pg_dump -U "${DB_USER}" -Fc bbh > "$STAGING/bbh-$STAMP.dump"

# 2. Uploaded originals (variant cache is regenerable and skipped)
docker run --rm -v "${STACK_NAME}_uploads":/data -v "$STAGING":/backup alpine \
  tar czf "/backup/uploads-$STAMP.tar.gz" -C /data uploads

# 3. Offsite: dedup + encrypted Borg archive, with retention pruning
borg create --stats "${BORG_REPO}::bbh-{now:%Y-%m-%d}" "$STAGING"
borg prune -v "${BORG_REPO}" --keep-daily=7 --keep-weekly=4 --keep-monthly=6

# Keep only the last 3 local staged copies
ls -1t "$STAGING"/bbh-*.dump | tail -n +4 | xargs -r rm --
ls -1t "$STAGING"/uploads-*.tar.gz | tail -n +4 | xargs -r rm --

# --- Restore runbook ---
# 1. docker compose up -d postgres
# 2. cat bbh-DATE.dump | docker compose exec -T postgres pg_restore -U $DB_USER -d bbh --clean --if-exists
# 3. docker run --rm -v ${STACK_NAME}_uploads:/data -v $STAGING:/backup alpine \
#      tar xzf /backup/uploads-DATE.tar.gz -C /data
# 4. docker compose up -d   (image variants regenerate on first request)
