#!/usr/bin/env bash
# Move this stack's database from the legacy Postgres 16 volume onto the Postgres
# major that compose.yml now runs (18), by dump & restore.
#
# Run ONCE per stack, on the server, from deploy/ — after `git pull` brought in the
# new compose.yml, and BEFORE ./update.sh. Beta first, then Prod: an 18 dump cannot
# be restored into 16, so sync-data.sh only works while Beta is the newer one.
# See README "Postgres major upgrade".
#
# Why a new volume: an 18 server cannot open a 16 data directory, and the 18+ image
# moved its layout (volume at /var/lib/postgresql, PGDATA in a major-version
# subdirectory). The data therefore moves to ${STACK_NAME}_pgdata; the legacy
# ${STACK_NAME}_postgres_data is only ever read, never modified.
#
# What it does, in order:
#   1. Safety checks: the legacy volume holds an older cluster, the new volume is
#      absent or holds no tables, no unconsumed dump waits in restore/. Asks for
#      confirmation (skip with --yes).
#   2. Stops the stack — the site is down from here until step 6 (~1–2 minutes).
#   3. Starts a throwaway postgres:<old>-alpine container on the legacy volume (no
#      network), pg_dumps the database into restore/ (+ a copy in backups/) and
#      records the exact row count of every table.
#   4. Starts postgres + restore only: the new server initialises the new volume and
#      the restore service loads the dump.
#   5. Compares the row counts. Any mismatch stops here, with Phoenix still down.
#   6. Starts the whole stack and waits for Phoenix to report healthy.
#
# Rollback: the legacy volume is untouched. Check out the previous deploy/compose.yml
# and `docker compose up -d` — writes made after the upgrade are lost.
#
# Flags:
#   --yes        no interactive confirmation
#   -h | --help
set -euo pipefail

# Always operate from the directory this script lives in (deploy/).
cd "$(dirname "$0")"

ASSUME_YES=0
for arg in "$@"; do
  case "$arg" in
    --yes) ASSUME_YES=1 ;;
    -h|--help) awk 'NR==1{next} /^#/{sub(/^# ?/,""); print; next} {exit}' "$0"; exit 0 ;;
    *) echo "unknown argument: $arg (try --help)" >&2; exit 2 ;;
  esac
done

die() { echo "upgrade-postgres: $*" >&2; exit 1; }
[[ -f .env ]] || die ".env not found in $(pwd). Run ./setup.sh first."

# Read single keys without sourcing: .env holds $$-escaped bcrypt hashes etc.
envval() { sed -n "s/^$1=//p" .env | head -n1 | sed -e 's/^"//' -e 's/"$//'; }

STACK="$(envval STACK_NAME)"; STACK="${STACK:-bbh}"
DB_USER="$(envval DB_USER)"
PHX_HOST="$(envval PHX_HOST)"
[[ -n "$DB_USER" ]] || die "DB_USER missing in .env"

DB=bbh
LEGACY_VOL="${STACK}_postgres_data"
NEW_VOL="${STACK}_pgdata"
COMPOSE=(docker compose --env-file .env -f compose.yml)

# Exact per-table row counts, identical query on both sides of the move.
COUNT_SQL="SELECT table_name || ' ' || (xpath('/row/c/text()',
  query_to_xml(format('SELECT count(*) AS c FROM public.%I', table_name), false, true, '')))[1]::text
  FROM information_schema.tables
  WHERE table_schema = 'public' AND table_type = 'BASE TABLE'
  ORDER BY table_name"
TABLES_SQL="SELECT count(*) FROM pg_catalog.pg_tables WHERE schemaname = 'public'"

volume_exists() { docker volume inspect "$1" >/dev/null 2>&1; }

# --- Throwaway server on a volume (no network; local socket, trust auth) -------
TMP=""
start_tmp() { # image volume mountpoint
  TMP="${STACK}-pgupgrade-$$"
  docker run -d --rm --name "$TMP" --network none -v "$2:$3" "$1" >/dev/null
  for _ in $(seq 1 60); do
    if docker exec "$TMP" pg_isready -q -U "$DB_USER" -d "$DB" 2>/dev/null; then return 0; fi
    sleep 1
  done
  docker logs "$TMP" >&2 2>&1 || true
  die "throwaway $1 on $2 did not become ready"
}
stop_tmp() { if [[ -n "$TMP" ]]; then docker stop "$TMP" >/dev/null 2>&1 || true; TMP=""; fi; }
tmp_sql() { docker exec "$TMP" psql -U "$DB_USER" -d "$DB" -XtAq -v ON_ERROR_STOP=1 -c "$1"; }

WORK="$(mktemp -d)"
STOPPED=0 DONE=0 DUMP=""
cleanup() {
  stop_tmp
  rm -rf "$WORK"
  if [[ "$STOPPED" -eq 1 && "$DONE" -ne 1 ]]; then
    {
      echo
      echo "upgrade-postgres: FAILED — the stack is left stopped (Phoenix down)."
      echo "  The legacy volume $LEGACY_VOL is untouched."
      [[ -n "$DUMP" ]] && echo "  Dump of the old database: $DUMP (copy in backups/)"
      echo "  Back to the previous state: see README \"Postgres major upgrade\" → Rollback."
    } >&2
  fi
}
trap cleanup EXIT

# --- 1. Safety checks ---------------------------------------------------------
NEW_IMAGE="$("${COMPOSE[@]}" config --images | grep -m1 -E '(^|/)postgres:[0-9]+')" \
  || die "no postgres:<major> image found in compose.yml"
NEW_MAJOR="$(sed -E 's#^.*postgres:([0-9]+).*$#\1#' <<<"$NEW_IMAGE")"

volume_exists "$LEGACY_VOL" || die "legacy volume $LEGACY_VOL not found — nothing to upgrade"
OLD_MAJOR="$(docker run --rm --network none -v "$LEGACY_VOL":/v:ro --entrypoint cat \
  "$NEW_IMAGE" /v/PG_VERSION 2>/dev/null || true)"
[[ "$OLD_MAJOR" =~ ^[0-9]+$ ]] || die "$LEGACY_VOL holds no Postgres cluster — nothing to upgrade"
(( OLD_MAJOR < NEW_MAJOR )) || die "legacy cluster is Postgres $OLD_MAJOR, compose runs $NEW_MAJOR — nothing to upgrade"
OLD_IMAGE="postgres:${OLD_MAJOR}-alpine"

shopt -s nullglob
pending=(restore/*.dump)
shopt -u nullglob
(( ${#pending[@]} == 0 )) || die "unconsumed dump(s) in restore/: ${pending[*]} — move them away first"

cat <<EOF
Stack:    $PHX_HOST  (stack $STACK, $(pwd))
Upgrade:  Postgres $OLD_MAJOR ($LEGACY_VOL, left untouched)
       -> $NEW_IMAGE ($NEW_VOL)
The site is DOWN while the data is copied (usually 1–2 minutes).
EOF
if [[ "$ASSUME_YES" -ne 1 ]]; then
  read -r -p "Type the host to continue: " answer </dev/tty
  [[ "$answer" == "$PHX_HOST" ]] || die "aborted"
fi

STAMP="$(date +%Y%m%d-%H%M%S)"
mkdir -p backups restore

# --- 2. Stop the stack --------------------------------------------------------
echo "==> Stopping the stack"
STOPPED=1
"${COMPOSE[@]}" stop
[[ -z "$(docker ps -q --filter volume="$LEGACY_VOL")" ]] \
  || die "a running container still uses $LEGACY_VOL: $(docker ps --filter volume="$LEGACY_VOL" --format '{{.Names}}')"

# A new volume left by an `up -d` before this script holds an empty cluster (the
# restore tripwire kept Phoenix off it). Clear that; never touch one with tables.
if volume_exists "$NEW_VOL"; then
  echo "==> $NEW_VOL already exists — checking that it holds no data"
  if docker run --rm --network none -v "$NEW_VOL":/v:ro --entrypoint test "$NEW_IMAGE" \
      -f "/v/$NEW_MAJOR/docker/PG_VERSION"; then
    start_tmp "$NEW_IMAGE" "$NEW_VOL" /var/lib/postgresql
    tables="$(tmp_sql "$TABLES_SQL")"
    stop_tmp
    [[ "$tables" == "0" ]] || die "$NEW_VOL already holds $tables table(s) — already upgraded? Not touching it."
  fi
  "${COMPOSE[@]}" rm -f postgres restore >/dev/null
  [[ -z "$(docker ps -aq --filter volume="$NEW_VOL")" ]] \
    || die "$NEW_VOL is still attached to: $(docker ps -a --filter volume="$NEW_VOL" --format '{{.Names}}')"
  docker volume rm "$NEW_VOL" >/dev/null
  echo "    removed the empty $NEW_VOL"
fi

# --- 3. Dump the old cluster --------------------------------------------------
echo "==> Dumping '$DB' from a throwaway $OLD_IMAGE on $LEGACY_VOL"
start_tmp "$OLD_IMAGE" "$LEGACY_VOL" /var/lib/postgresql/data
docker exec "$TMP" pg_dump -U "$DB_USER" -Fc "$DB" > "$WORK/db.dump"
docker exec -i "$TMP" pg_restore -l < "$WORK/db.dump" > "$WORK/db.toc"
grep -q ' TABLE ' "$WORK/db.toc" || die "the dump lists no tables — refusing to continue"
tmp_sql "$COUNT_SQL" > "$WORK/old.counts"
stop_tmp
cp "$WORK/db.dump" "backups/pg${OLD_MAJOR}-final-$STAMP.dump"
# Copied in as *.partial and renamed: the restore service only ever sees a whole *.dump.
DUMP="restore/pg${OLD_MAJOR}-to-pg${NEW_MAJOR}-$STAMP.dump"
cp "$WORK/db.dump" "$DUMP.partial"
mv "$DUMP.partial" "$DUMP"
echo "    $(wc -l < "$WORK/old.counts") tables, dump $(du -h "$DUMP" | cut -f1)"

# --- 4. New server + restore (Phoenix stays down) -----------------------------
echo "==> Starting Postgres $NEW_MAJOR on $NEW_VOL and restoring"
"${COMPOSE[@]}" up -d --wait postgres
# Recreated so the status polled below is this run's, never a stale exit.
"${COMPOSE[@]}" up -d --force-recreate --no-deps restore
RESTORE_ID="$("${COMPOSE[@]}" ps -aq restore)"
[[ -n "$RESTORE_ID" ]] || die "restore container not found"
for _ in $(seq 1 900); do
  [[ "$(docker inspect -f '{{.State.Status}}' "$RESTORE_ID")" == "exited" ]] && break
  sleep 1
done
code="$(docker inspect -f '{{.State.ExitCode}}' "$RESTORE_ID")"
if [[ "$(docker inspect -f '{{.State.Status}}' "$RESTORE_ID")" != "exited" || "$code" != "0" ]]; then
  "${COMPOSE[@]}" logs restore >&2 || true
  die "restore did not complete successfully (exit $code)"
fi

# --- 5. Verify ----------------------------------------------------------------
echo "==> Comparing row counts"
# docker exec on the container id, not `compose exec` (see AGENTS.md: it segfaults on
# some Docker versions).
PG_ID="$("${COMPOSE[@]}" ps -q postgres)"
docker exec "$PG_ID" psql -U "$DB_USER" -d "$DB" -XtAq -v ON_ERROR_STOP=1 \
  -c "$COUNT_SQL" > "$WORK/new.counts"
diff -u "$WORK/old.counts" "$WORK/new.counts" >&2 \
  || die "row counts differ between Postgres $OLD_MAJOR and $NEW_MAJOR (diff above)"
VERSION="$(docker exec "$PG_ID" psql -U "$DB_USER" -d "$DB" -XtAq -c 'SHOW server_version')"
echo "    all $(wc -l < "$WORK/new.counts") tables match on Postgres $VERSION"

# --- 6. Whole stack -----------------------------------------------------------
echo "==> Starting the stack"
"${COMPOSE[@]}" up -d
PHX_ID="$("${COMPOSE[@]}" ps -q phoenix)"
health=""
for _ in $(seq 1 60); do
  health="$(docker inspect -f '{{if .State.Health}}{{.State.Health.Status}}{{end}}' "$PHX_ID" 2>/dev/null || true)"
  [[ "$health" == "healthy" ]] && break
  sleep 5
done
DONE=1
if [[ "$health" != "healthy" ]]; then
  echo "upgrade-postgres: data is on Postgres $VERSION, but Phoenix is not healthy yet ($health)." >&2
  echo "  Check: ${COMPOSE[*]} logs phoenix" >&2
  exit 1
fi

cat <<EOF

==> Done: $PHX_HOST runs on Postgres $VERSION ($NEW_VOL).
    The old cluster stays in $LEGACY_VOL as the rollback path. Once you are
    satisfied (a few days), remove it with:
      ${COMPOSE[*]} rm -f restore && docker volume rm $LEGACY_VOL
    (compose re-creates it empty on the next up; that is harmless.)
EOF
