#!/usr/bin/env bash
# Update a running beta/prod deployment to the latest code + image.
#
# Does three things, in order:
#   1. git pull          — refresh this checkout (compose.yml, labels, this script,
#                          .env.example) from the default branch. Skipped with a
#                          warning if deploy/ was copied standalone (no .git).
#   2. docker compose pull   — fetch the newest image for the pinned IMAGE tag.
#   3. docker compose up -d  — recreate only what changed; Phoenix runs bin/migrate
#                          on startup, so schema migrations apply automatically.
#
# Beta tracks :beta (rolling), so a plain pull moves it forward. Prod pins an
# immutable :sha in .env — bump that tag first (or use ./setup.sh), then run this.
# To roll back, set IMAGE back to an earlier :sha-XXXXXXX in .env and re-run.
#
# Usage (on the server, from the deploy/ directory):
#   ./update.sh                 # git pull + compose pull + up -d  (whole stack)
#   ./update.sh --no-pull-code  # skip git pull (image/restart only)
#   ./update.sh -h | --help
set -euo pipefail

# Always operate from the directory this script lives in (deploy/).
cd "$(dirname "$0")"

PULL_CODE=1
for arg in "$@"; do
  case "$arg" in
    --no-pull-code) PULL_CODE=0 ;;
    -h|--help)
      # Print the leading comment header (skip the shebang, stop at first non-comment).
      awk 'NR==1{next} /^#/{sub(/^# ?/,""); print; next} {exit}' "$0"
      exit 0
      ;;
    *)
      echo "unknown argument: $arg (try --help)" >&2
      exit 2
      ;;
  esac
done

if [[ ! -f .env ]]; then
  echo "ERROR: .env not found in $(pwd). Run ./setup.sh first." >&2
  exit 1
fi

COMPOSE=(docker compose --env-file .env)

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

echo "==> docker compose pull"
"${COMPOSE[@]}" pull

echo "==> docker compose up -d"
"${COMPOSE[@]}" up -d

echo
echo "==> Done. Current state:"
"${COMPOSE[@]}" ps
echo
echo "Tip: follow the app coming up with"
echo "     ${COMPOSE[*]} logs -f phoenix"
