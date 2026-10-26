#!/usr/bin/env bash
# Update a running beta/prod deployment to the latest code + image.
#
# Does these things, in order:
#   1. git pull          — refresh this checkout (compose.yml, labels, this script,
#                          .env.example) from the default branch. Skipped with a
#                          warning if deploy/ was copied standalone (no .git).
#   2. (--latest / --tag only) pin IMAGE in .env to that tag, after a safety dump
#                          of the database into ./backups/ (the last 5 are kept).
#   3. docker compose pull   — fetch the image for the pinned IMAGE tag.
#   4. docker compose up -d  — recreate only what changed; Phoenix runs bin/migrate
#                          on startup, so schema migrations apply automatically.
#
# Beta tracks :beta (rolling), so a plain run moves it forward. Prod pins an
# immutable build tag (YYYYMMDD-HHMM-<sha>, see .github/workflows/build.yml);
# --latest asks GHCR for the newest one and pins it. To roll back, run
# --tag with the previous tag (printed after every switch). A migration is not
# undone by that — restore the safety dump for that.
#
# Usage (on the server, from the deploy/ directory):
#   ./update.sh                 # git pull + compose pull + up -d  (whole stack)
#   ./update.sh --latest        # pin the newest build tag, then update
#   ./update.sh --tag TAG       # pin TAG (e.g. for a rollback), then update
#   ./update.sh --yes           # with --latest/--tag: don't ask before switching
#   ./update.sh --no-pull-code  # skip git pull (image/restart only)
#   ./update.sh -h | --help
set -euo pipefail

# Always operate from the directory this script lives in (deploy/).
cd "$(dirname "$0")"

PULL_CODE=1 PIN="" ASSUME_YES=0 DUMP="" ROLLBACK=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    --no-pull-code) PULL_CODE=0 ;;
    --latest) PIN=latest ;;
    --tag)
      [[ -n "${2:-}" ]] || { echo "--tag needs a value (try --help)" >&2; exit 2; }
      PIN="$2"; shift ;;
    --yes) ASSUME_YES=1 ;;
    -h|--help)
      # Print the leading comment header (skip the shebang, stop at first non-comment).
      awk 'NR==1{next} /^#/{sub(/^# ?/,""); print; next} {exit}' "$0"
      exit 0
      ;;
    *)
      echo "unknown argument: $1 (try --help)" >&2
      exit 2
      ;;
  esac
  shift
done

if [[ ! -f .env ]]; then
  echo "ERROR: .env not found in $(pwd). Run ./setup.sh first." >&2
  exit 1
fi

COMPOSE=(docker compose --env-file .env)
dotenv() { sed -n "s/^$1=//p" .env | head -n1; }
die() { echo "ERROR: $*" >&2; exit 1; }

# Build tags as written by build.yml: UTC date + time + short commit SHA. They sort
# chronologically as plain strings, which is what "latest" relies on.
BUILD_TAG_RE='^[0-9]{8}-[0-9]{4}-[0-9a-f]{7}$'

# Newest build tag of a public GHCR repository ("owner/name"). The registry API
# pages its tag list (Link header); a full page means there may be another one.
latest_build_tag() {
  local repo="$1" token page tags last="" all=""
  token="$(curl -fsS "https://ghcr.io/token?scope=repository:${repo}:pull" |
    sed -n 's/.*"token":"\([^"]*\)".*/\1/p')"
  [[ -n "$token" ]] || return 1
  while :; do
    page="$(curl -fsS -H "Authorization: Bearer $token" \
      "https://ghcr.io/v2/${repo}/tags/list?n=1000${last:+&last=$last}")" || return 1
    tags="$(sed -n 's/.*"tags":\[\([^]]*\)\].*/\1/p' <<<"$page" | tr ',' '\n' | tr -d '"')"
    [[ -n "$tags" ]] || break
    all+="$tags"$'\n'
    [[ "$(wc -l <<<"$tags")" -ge 1000 ]] || break
    last="$(tail -n1 <<<"$tags")"
  done
  { grep -E "$BUILD_TAG_RE" <<<"$all" || true; } | sort | tail -n1
}

echo "==> Updating deployment in $(pwd)"

if [[ "$PULL_CODE" -eq 1 ]]; then
  if git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
    echo "==> git pull"
    git pull --ff-only
  else
    echo "==> git pull skipped (not a git checkout — deploy/ was copied standalone)"
  fi
else
  echo "==> git pull skipped (--no-pull-code)"
fi

if [[ -n "$PIN" ]]; then
  CURRENT="$(dotenv IMAGE)"
  REPO_REF="${CURRENT%:*}"
  REPO_REF="${REPO_REF:-ghcr.io/buterland-beckerhook/app}"
  [[ "$REPO_REF" == ghcr.io/* ]] || die "IMAGE ($CURRENT) is not on ghcr.io"

  if [[ "$PIN" == latest ]]; then
    echo "==> Looking up the newest build tag on GHCR"
    TAG="$(latest_build_tag "${REPO_REF#ghcr.io/}")" || die "GHCR tag lookup failed"
    [[ -n "$TAG" ]] || die "no build tag (YYYYMMDD-HHMM-<sha>) found on GHCR"
  else
    TAG="$PIN"
  fi
  TARGET="$REPO_REF:$TAG"

  if [[ "$TARGET" == "$CURRENT" ]]; then
    echo "==> Already on $TARGET"
  else
    echo "==> Switching IMAGE"
    echo "    from: $CURRENT"
    echo "    to:   $TARGET"
    old_sha="${CURRENT##*[-:]}" new_sha="${TAG##*-}"
    if [[ "$old_sha" =~ ^[0-9a-f]{7}$ && "$new_sha" =~ ^[0-9a-f]{7}$ && "$old_sha" != "$new_sha" ]]; then
      echo "    changes: https://github.com/${REPO_REF#ghcr.io/}/compare/$old_sha...$new_sha"
    fi
    if [[ "$ASSUME_YES" -ne 1 ]]; then
      [[ -t 0 ]] || die "not a terminal — pass --yes to switch without asking"
      read -r -p "Continue? [y/N] " answer
      [[ "$answer" == [yY]* ]] || { echo "Aborted."; exit 1; }
    fi

    # A failed migration is not undone by going back to the old image, only by
    # restoring the database — so take a dump before the new image can migrate.
    if [[ -n "$("${COMPOSE[@]}" ps -q postgres 2>/dev/null)" ]]; then
      mkdir -p backups
      DUMP="backups/pre-update-$(date +%Y%m%d-%H%M%S).dump"
      echo "==> Safety dump -> $DUMP"
      # No -t on exec: a TTY mangles the binary dump.
      if ! "${COMPOSE[@]}" exec -T postgres pg_dump -U "$(dotenv DB_USER)" -Fc bbh > "$DUMP.tmp"; then
        rm -f "$DUMP.tmp"
        die "safety dump failed — IMAGE left unchanged"
      fi
      mv "$DUMP.tmp" "$DUMP"
      # shellcheck disable=SC2012
      ls -1t backups/pre-update-*.dump 2>/dev/null | tail -n +6 | xargs -r rm --
    else
      echo "==> Safety dump skipped (postgres is not running)"
      DUMP=""
    fi

    # Rewrite through cat so .env keeps its owner and mode (it holds secrets).
    if grep -q '^IMAGE=' .env; then
      sed "s|^IMAGE=.*|IMAGE=$TARGET|" .env > .env.tmp
      cat .env.tmp > .env
      rm -f .env.tmp
    else
      echo "IMAGE=$TARGET" >> .env
    fi
    ROLLBACK="$CURRENT"
  fi
fi

echo "==> docker compose pull"
"${COMPOSE[@]}" pull

echo "==> docker compose up -d"
"${COMPOSE[@]}" up -d

echo
echo "==> Done. Current state:"
"${COMPOSE[@]}" ps
echo
if [[ -n "$ROLLBACK" ]]; then
  echo "Roll back the image with: $0 --tag ${ROLLBACK##*:}"
  [[ -z "$DUMP" ]] || echo "Database before the switch:  $(pwd)/$DUMP"
  echo
fi
echo "Tip: follow the app coming up with"
echo "     ${COMPOSE[*]} logs -f phoenix"
