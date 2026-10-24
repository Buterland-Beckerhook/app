#!/usr/bin/env bash
# Nightly backup of one stack (Prod): Postgres dump + uploaded originals, pushed
# offsite into an encrypted Borg repository (a Hetzner Storage Box).
#
# Each run writes two archives per stack, so each restores in the format the
# `restore` service (restore-entrypoint.sh) consumes:
#   <STACK_NAME>-db-YYYY-MM-DD       bbh-YYYY-MM-DD.dump (pg_dump -Fc)
#   <STACK_NAME>-uploads-YYYY-MM-DD  uploads/ (originals only; the variant cache and
#                                    the map archive are regenerable)
# Both go in uncompressed (dump with -Z0, uploads straight from the volume) so Borg's
# chunk dedup works across nights; Borg compresses with zstd itself.
#
# Config: /etc/bbh-backup.env (root, chmod 600; override the path with BBH_BACKUP_ENV):
#   BORG_REPO=ssh://uXXXXXX@uXXXXXX.your-storagebox.de:23/./bbh-borg
#   BORG_PASSPHRASE=...
#   BORG_RSH="ssh -i /root/.ssh/bbh-backup -o BatchMode=yes"
#   BORG_REMOTE_PATH=borg-1.4      # match the server-side borg to the local major.minor
#   HC_PING_URL=https://hc-ping.com/<uuid>   # optional healthchecks.io check
# DB_USER and STACK_NAME come from the stack's .env (written by setup.sh).
#
# Usage (as root, from cron):
#   15 3 * * *  /path/to/deploy/backup.sh >> /var/log/bbh-backup.log 2>&1
#   ./backup.sh init      # one-time: create the repo + print the key to store safely
#   ./backup.sh           # back up, prune, compact (and verify the repo on Sundays)
#   ./backup.sh -h | --help
#
# Restore (see deploy/README.md, "Backups"):
#   borg list "$BORG_REPO"
#   borg extract    "$BORG_REPO::bbh-prod-db-DATE"          # -> ./bbh-DATE.dump
#   borg export-tar "$BORG_REPO::bbh-prod-uploads-DATE" uploads-DATE.tar.gz
#   then drop both into deploy/restore/ and `up -d` (stop phoenix first).
set -euo pipefail

COMPOSE_DIR="$(cd "$(dirname "$0")" && pwd)"
CONFIG="${BBH_BACKUP_ENV:-/etc/bbh-backup.env}"
STAGING="/var/backups/bbh"

case "${1:-}" in
  -h|--help) sed -n '2,/^set -euo/{/^set -euo/d;s/^# \{0,1\}//;p;}' "$0"; exit 0 ;;
  init|"") ;;
  *) echo "unknown argument: $1 (see --help)" >&2; exit 2 ;;
esac

[[ -r "$CONFIG" ]] || { echo "missing $CONFIG (see --help)" >&2; exit 1; }
set -a
# shellcheck source=/dev/null
. "$CONFIG"
set +a
: "${BORG_REPO:?BORG_REPO not set in $CONFIG}"
: "${BORG_PASSPHRASE:?BORG_PASSPHRASE not set in $CONFIG}"

dotenv() { sed -n "s/^$1=//p" "$COMPOSE_DIR/.env" 2>/dev/null | head -n1; }
STACK_NAME="${STACK_NAME:-$(dotenv STACK_NAME)}"
STACK_NAME="${STACK_NAME:-bbh}"
DB_USER="${DB_USER:-$(dotenv DB_USER)}"
: "${DB_USER:?DB_USER not found in $COMPOSE_DIR/.env}"

if [[ "${1:-}" == init ]]; then
  borg init --encryption=repokey-blake2 "$BORG_REPO"
  echo
  echo "Repo created. Store the passphrase AND this key outside the server"
  echo "(password manager) — without both, the backup cannot be read:"
  echo
  borg key export --paper "$BORG_REPO"
  exit 0
fi

# --- Monitoring: healthchecks.io start/success/fail pings (no-op without a URL) ---
ping_hc() {
  [[ -n "${HC_PING_URL:-}" ]] || return 0
  curl -fsS -m 10 --retry 3 -o /dev/null --data-raw "${2:-}" "$HC_PING_URL$1" || true
}
LOG="$(mktemp)"
on_exit() {
  local rc=$?
  if (( rc == 0 )); then ping_hc "" "$(tail -c 10000 "$LOG")"; else ping_hc "/fail" "$(tail -c 10000 "$LOG")"; fi
  rm -f "$LOG"
}
trap on_exit EXIT
exec > >(tee -a "$LOG") 2>&1
ping_hc "/start"

# One run at a time (a slow upload must not overlap the next night's run).
exec 9>/run/lock/bbh-backup.lock
flock -n 9 || { echo "another backup is still running" >&2; exit 1; }

STAMP="$(date +%F)"
echo "==> $(date -Is) backup of $STACK_NAME"
mkdir -p "$STAGING"
chmod 700 "$STAGING"

# 1. Postgres, uncompressed custom format (restorable with pg_restore). --env-file so
#    the compose project name (name: ${STACK_NAME}) resolves regardless of cron's cwd.
#    Written to a temp name first so a failed dump never looks like a good one.
DUMP="$STAGING/bbh-$STAMP.dump"
docker compose --env-file "$COMPOSE_DIR/.env" -f "$COMPOSE_DIR/compose.yml" exec -T postgres \
  pg_dump -U "$DB_USER" -Fc -Z0 bbh > "$DUMP.tmp"
mv "$DUMP.tmp" "$DUMP"

# 2. Offsite. Archives store relative paths (bbh-DATE.dump, uploads/…), which is exactly
#    what restore-entrypoint.sh expects after extract / export-tar.
UPLOADS_DIR="$(docker volume inspect -f '{{ .Mountpoint }}' "${STACK_NAME}_uploads")"
[[ -d "$UPLOADS_DIR/uploads" ]] || { echo "no uploads/ in $UPLOADS_DIR" >&2; exit 1; }

# borg exits 1 on warnings (e.g. an upload saved while it was read); only >1 is an error.
archive() {
  local dir=$1 name=$2; shift 2
  local rc=0
  (cd "$dir" && borg create --stats --compression zstd,6 "::$STACK_NAME-$name-{now:%Y-%m-%d}" "$@") || rc=$?
  (( rc <= 1 )) || exit "$rc"
}
archive "$STAGING" db "$(basename "$DUMP")"
archive "$UPLOADS_DIR" uploads uploads

# 3. Retention, per archive series, then free the space on the Storage Box.
for series in db uploads; do
  borg prune --list --glob-archives "$STACK_NAME-$series-*" \
    --keep-daily=7 --keep-weekly=4 --keep-monthly=6
done
borg compact

# 4. Weekly integrity check of the repository (runs server-side, cheap on traffic).
if [[ "$(date +%u)" == 7 ]]; then
  borg check --repository-only
fi

# Keep the last 3 dumps locally for a quick restore without touching the Storage Box.
# shellcheck disable=SC2012 # names are our own, no odd characters expected
ls -1t "$STAGING"/bbh-*.dump | tail -n +4 | xargs -r rm --
echo "==> $(date -Is) done"
