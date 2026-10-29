#!/usr/bin/env bash
# Copy the data (database + uploads) of one stack into another on the same host.
#
# Typical use: bring Beta up to the current Prod content before testing a new
# feature against real data. Works in either direction, but a Prod target needs
# an explicit extra flag.
#
#   ./sync-data.sh --from /srv/bbh-prod/deploy --to /srv/bbh-beta/deploy
#
# Both arguments are deploy/ directories that hold a .env written by setup.sh.
# STACK_NAME, DB_USER and PHX_HOST are read from those files.
#
# What it does, in order:
#   1. Safety checks (different stacks, target is Beta unless --allow-prod-target),
#      then asks for confirmation (skip with --yes).
#   2. pg_dump of the source DB (live; pg_dump reads one consistent snapshot).
#   3. Safety dump of the target DB into <target>/backups/ (keeps the last 5).
#   4. Stops the target's phoenix, drops + recreates its DB, restores the dump
#      in a single transaction.
#   5. Sanitizes the target DB (see SANITIZE_SQL below): no push subscriptions,
#      sessions, MCP/API tokens, queued jobs, Postfach tickets or login log are
#      carried over.
#   6. Copies the uploads volume (originals + variant cache) source -> target.
#   7. Starts the target stack; Phoenix runs bin/migrate on top, so a target
#      image with newer migrations than the source just applies them.
#
# The source stack keeps running throughout.
#
# Flags:
#   --from DIR             source deploy/ directory            (required)
#   --to DIR               target deploy/ directory            (required)
#   --yes                  no interactive confirmation (for scripts/cron)
#   --allow-prod-target    permit a target whose PHX_HOST does not start with "beta."
#   --no-uploads           sync only the database
#   -h | --help
#
# After a sync, logins on the target need a magic link (e-mail): passkeys are
# bound to the host name and therefore do not work across stacks.
set -euo pipefail

SRC_DIR="" DST_DIR="" ASSUME_YES=0 ALLOW_PROD=0 WITH_UPLOADS=1
while [[ $# -gt 0 ]]; do
  case "$1" in
    --from) SRC_DIR="${2:-}"; shift 2 ;;
    --to) DST_DIR="${2:-}"; shift 2 ;;
    --yes) ASSUME_YES=1; shift ;;
    --allow-prod-target) ALLOW_PROD=1; shift ;;
    --no-uploads) WITH_UPLOADS=0; shift ;;
    -h|--help) awk 'NR==1{next} /^#/{sub(/^# ?/,""); print; next} {exit}' "$0"; exit 0 ;;
    *) echo "unknown argument: $1 (try --help)" >&2; exit 2 ;;
  esac
done

die() { echo "sync-data: $*" >&2; exit 1; }
[[ -n "$SRC_DIR" && -n "$DST_DIR" ]] || die "--from and --to are required (try --help)"
SRC_DIR="$(cd "$SRC_DIR" && pwd)" || die "source dir not found"
DST_DIR="$(cd "$DST_DIR" && pwd)" || die "target dir not found"
[[ -f "$SRC_DIR/.env" ]] || die "no .env in $SRC_DIR"
[[ -f "$DST_DIR/.env" ]] || die "no .env in $DST_DIR"

# Read single keys without sourcing: .env holds $$-escaped bcrypt hashes etc.
envval() { sed -n "s/^$2=//p" "$1/.env" | head -n1 | sed -e 's/^"//' -e 's/"$//'; }

SRC_STACK="$(envval "$SRC_DIR" STACK_NAME)"; SRC_STACK="${SRC_STACK:-bbh}"
DST_STACK="$(envval "$DST_DIR" STACK_NAME)"; DST_STACK="${DST_STACK:-bbh}"
SRC_DB_USER="$(envval "$SRC_DIR" DB_USER)"
DST_DB_USER="$(envval "$DST_DIR" DB_USER)"
SRC_HOST="$(envval "$SRC_DIR" PHX_HOST)"
DST_HOST="$(envval "$DST_DIR" PHX_HOST)"
[[ -n "$SRC_DB_USER" && -n "$DST_DB_USER" ]] || die "DB_USER missing in a .env"

[[ "$SRC_DIR" != "$DST_DIR" ]] || die "source and target are the same directory"
[[ "$SRC_STACK" != "$DST_STACK" ]] || die "source and target share STACK_NAME=$SRC_STACK (same volumes!)"
if [[ "$DST_HOST" != beta.* && "$ALLOW_PROD" -ne 1 ]]; then
  die "target PHX_HOST=$DST_HOST is not a beta host; pass --allow-prod-target if you really mean it"
fi

src() { docker compose --env-file "$SRC_DIR/.env" -f "$SRC_DIR/compose.yml" "$@"; }
dst() { docker compose --env-file "$DST_DIR/.env" -f "$DST_DIR/compose.yml" "$@"; }

cat <<EOF
Source: $SRC_HOST  (stack $SRC_STACK, $SRC_DIR)
Target: $DST_HOST  (stack $DST_STACK, $DST_DIR)
The target database$([[ $WITH_UPLOADS -eq 1 ]] && echo " and uploads") will be REPLACED.
EOF
if [[ "$ASSUME_YES" -ne 1 ]]; then
  read -r -p "Type the target host to continue: " answer </dev/tty
  [[ "$answer" == "$DST_HOST" ]] || die "aborted"
fi

[[ -n "$(src ps -q postgres)" ]] || die "source postgres is not running"

STAMP="$(date +%Y%m%d-%H%M%S)"
WORK="$(mktemp -d)"
STOPPED=0 DONE=0
cleanup() {
  rm -rf "$WORK"
  if [[ "$STOPPED" -eq 1 && "$DONE" -ne 1 ]]; then
    echo "sync-data: FAILED — target phoenix left stopped (no half-restored DB is served)." >&2
    echo "           Safety dump of the previous target DB: $BACKUPS/pre-sync-$STAMP.dump" >&2
  fi
}
trap cleanup EXIT
BACKUPS="$DST_DIR/backups"
mkdir -p "$BACKUPS"

echo "==> Dumping source database"
# No -t on exec: a TTY mangles the binary dump.
src exec -T postgres pg_dump -U "$SRC_DB_USER" -Fc bbh > "$WORK/source.dump"
[[ -s "$WORK/source.dump" ]] || die "source dump is empty"

echo "==> Starting target postgres"
dst up -d --wait postgres

echo "==> Safety dump of target -> $BACKUPS/pre-sync-$STAMP.dump"
if ! dst exec -T postgres pg_dump -U "$DST_DB_USER" -Fc bbh > "$BACKUPS/pre-sync-$STAMP.dump"; then
  rm -f "$BACKUPS/pre-sync-$STAMP.dump"
  echo "    (target DB not dumpable — probably new/empty; continuing without safety dump)"
fi
# shellcheck disable=SC2012
ls -1t "$BACKUPS"/pre-sync-*.dump 2>/dev/null | tail -n +6 | xargs -r rm --

echo "==> Stopping target phoenix"
# From here on a failure leaves the target app stopped (rather than serving a
# half-restored DB); cleanup() says so.
STOPPED=1
dst stop phoenix

echo "==> Recreating target database and restoring"
dst exec -T postgres dropdb -U "$DST_DB_USER" --if-exists --force bbh
dst exec -T postgres createdb -U "$DST_DB_USER" bbh
dst exec -T postgres pg_restore -U "$DST_DB_USER" -d bbh \
  --no-owner --no-privileges --single-transaction --exit-on-error < "$WORK/source.dump"

echo "==> Sanitizing target database"
# Everything here is either bound to the source host/keys or would act on it:
#   push_subscriptions  — real subscribers; a test publish must never reach them
#                         (and they are tied to the source's VAPID key anyway)
#   users_tokens        — sessions + magic links of the source
#   api_tokens, oauth_* — MCP/API credentials of the source
#   oban_*              — queued/scheduled jobs (pushes, reminders) of the source
#   tickets, ticket_*   — the Postfach: personal data (requests, membership
#                         applications with IBAN). Encrypted with the source's keys,
#                         unreadable on a target with its own — but it does not
#                         belong there at all.
#   auth_events         — the source's login log (IP addresses)
# Tables are truncated in ONE statement so FKs between them are fine; a table
# missing in an older schema is skipped.
dst exec -T postgres psql -U "$DST_DB_USER" -d bbh -v ON_ERROR_STOP=1 -q <<'SQL'
DO $$
DECLARE
  wanted text[] := ARRAY['push_subscriptions','users_tokens','api_tokens',
                         'oauth_codes','oauth_clients','oban_jobs','oban_peers',
                         'ticket_attachments','ticket_messages','ticket_events',
                         'tickets','auth_events'];
  present text;
BEGIN
  SELECT string_agg(format('%I', t), ', ') INTO present
    FROM unnest(wanted) AS t WHERE to_regclass(t) IS NOT NULL;
  IF present IS NOT NULL THEN
    EXECUTE 'TRUNCATE ' || present;
    RAISE NOTICE 'truncated: %', present;
  END IF;
END $$;
SQL

if [[ "$WITH_UPLOADS" -eq 1 ]]; then
  echo "==> Copying uploads volume ${SRC_STACK}_uploads -> ${DST_STACK}_uploads"
  docker volume inspect "${SRC_STACK}_uploads" >/dev/null || die "volume ${SRC_STACK}_uploads not found"
  docker volume inspect "${DST_STACK}_uploads" >/dev/null 2>&1 || docker volume create "${DST_STACK}_uploads" >/dev/null
  # Variant cache is copied too: it matches the copied originals 1:1 and saves the
  # target a libvips regeneration spike. The release runs as uid 65534 (nobody).
  docker run --rm \
    -v "${SRC_STACK}_uploads":/src:ro \
    -v "${DST_STACK}_uploads":/dst \
    alpine sh -euc '
      find /dst -mindepth 1 -maxdepth 1 -exec rm -rf {} +
      cp -a /src/. /dst/
      chown -R 65534:0 /dst
    '
fi

echo "==> Starting target stack (migrations run on boot)"
dst up -d
STOPPED=0  # phoenix is started again; a failure below is a health problem, not a stopped app
# Not `up --wait`: the one-shot restore service exits, which older Compose
# versions report as a failure. Poll phoenix's own healthcheck instead.
PHX="$(dst ps -q phoenix)"
for _ in $(seq 1 60); do
  status="$(docker inspect -f '{{.State.Health.Status}}' "$PHX" 2>/dev/null || echo unknown)"
  [[ "$status" == healthy ]] && break
  sleep 5
done
[[ "$status" == healthy ]] || die "phoenix not healthy after 5 min (status: $status) — check: docker compose --env-file $DST_DIR/.env logs phoenix"
DONE=1
echo
echo "Done: $DST_HOST now has the data of $SRC_HOST (as of $STAMP)."
echo "Log in on $DST_HOST via magic link — passkeys from $SRC_HOST do not work there."
