#!/bin/sh
# One-shot restore, run as its own compose service BEFORE Phoenix boots.
#
# Contract: if ./restore (mounted at /restore) contains a *.dump produced by
# deploy/backup.sh (pg_dump -Fc), restore it into the DB; if an uploads tarball
# (uploads*.tar.gz) is present too, unpack it into the uploads volume. On success
# each consumed file is renamed to *.restored so restarts are a no-op — dropping a
# fresh *.dump into ./restore is the (one-time) trigger to restore again.
#
# Sequence across the stack: postgres healthy -> THIS restore -> Phoenix runs
# bin/migrate (on top of the restored schema) -> server. A missing dump is a
# clean no-op (exit 0); a failed restore exits non-zero so Phoenix won't start on
# a half-restored DB (compose: phoenix depends_on restore = completed_successfully).
#
# Env (from compose): PGHOST, PGUSER, PGPASSWORD, PGDATABASE (=bbh). pg_restore
# reads PG* automatically.
set -eu

RESTORE_DIR=/restore
DATA_DIR=/data

# Newest matching file, or empty. Guarded so `set -e` + no-match doesn't abort.
newest() {
  # shellcheck disable=SC2012 # names are our own, no odd characters expected
  ls -1t "$@" 2>/dev/null | head -n1 || true
}

DUMP="$(newest "$RESTORE_DIR"/*.dump)"
if [ -z "$DUMP" ]; then
  echo "restore: no *.dump in $RESTORE_DIR — nothing to do."
  exit 0
fi

echo "restore: restoring database '$PGDATABASE' from $DUMP"
# --clean --if-exists: drop & recreate objects so a full dump replaces the
# (empty, freshly-created) schema cleanly. --no-owner/--no-privileges: role-agnostic.
# Runs before Phoenix, so there are no pool connections to fight.
pg_restore --clean --if-exists --no-owner --no-privileges -d "$PGDATABASE" "$DUMP"

UPLOADS="$(newest "$RESTORE_DIR"/uploads*.tar.gz)"
if [ -n "$UPLOADS" ]; then
  echo "restore: unpacking uploads from $UPLOADS into $DATA_DIR"
  # Tarballs from backup.sh have a top-level uploads/ dir. Replace originals and
  # drop the regenerable variant cache so WebP variants rebuild on demand.
  rm -rf "${DATA_DIR:?}/uploads"
  tar xzf "$UPLOADS" -C "$DATA_DIR"
  rm -rf "${DATA_DIR:?}/uploads_cache"/* 2>/dev/null || true
  # This one-shot runs as root (postgres image); the Phoenix release runs as
  # `nobody` (uid 65534, see app/Dockerfile) and must be able to write new
  # uploads + regenerate the variant cache. Hand the volume to that uid.
  chown -R 65534:0 "$DATA_DIR"
fi

# Mark ALL consumed files so a restart never re-restores over live data — and so
# a stale second dump can't silently become "newest" on the next boot.
for f in "$RESTORE_DIR"/*.dump;            do [ -e "$f" ] && mv "$f" "$f.restored"; done
for f in "$RESTORE_DIR"/uploads*.tar.gz;   do [ -e "$f" ] && mv "$f" "$f.restored"; done

echo "restore: done."
