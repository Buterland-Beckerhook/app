#!/usr/bin/env bash
# Idempotent bootstrap for the beta/prod stack's .env.
#
# Generates every secret locally with `openssl` (no image needed — so there is no
# chicken-and-egg with the GHCR pull) and writes a correct .env. Re-running only
# fills values that are still missing; existing values are preserved verbatim.
#
# CRUCIAL: every value is written with `$` doubled to `$$`. Docker Compose
# interpolates .env values into both labels and `environment:`; a single `$`
# (e.g. in a bcrypt Basic-Auth hash) is otherwise mangled/truncated, which
# silently disables Traefik Basic-Auth and serves the site unprotected.
#
# Usage (on the server, from the deploy/ directory):
#   ./setup.sh              # interactive
#   ./setup.sh --yes        # non-interactive: accept all generated/mode defaults
#   ./setup.sh --prod       # preset prod-mode defaults (default is beta)
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ENV_FILE="$SCRIPT_DIR/.env"
COMPOSE_FILE="$SCRIPT_DIR/compose.yml"

ASSUME_YES=0
MODE="${MODE:-}"

usage() {
  cat <<'EOF'
Usage: ./setup.sh [--yes] [--beta|--prod]
  --yes    non-interactive: accept all generated/mode defaults
  --beta   preset beta-mode defaults (this is the default)
  --prod   preset prod-mode defaults
Writes deploy/.env. Idempotent: fills only values that are still missing;
existing values (and any operator-added keys) are preserved.
EOF
}

for arg in "$@"; do
  case "$arg" in
    -y|--yes)  ASSUME_YES=1 ;;
    --beta)    MODE=beta ;;
    --prod)    MODE=prod ;;
    -h|--help) usage; exit 0 ;;
    *) echo "setup.sh: unknown argument '$arg'" >&2; exit 2 ;;
  esac
done

command -v openssl >/dev/null 2>&1 || { echo "setup.sh: openssl is required." >&2; exit 1; }

# Scratch (VAPID pem etc.). The .env temp is written next to $ENV_FILE instead so
# the final rename is a same-filesystem atomic mv.
TMP="$(mktemp -d)"
ENV_TMP=""
trap 'rm -rf "$TMP"; [[ -n "$ENV_TMP" ]] && rm -f "$ENV_TMP"' EXIT

# --- helpers -----------------------------------------------------------------

# Double every '$' so the value survives Compose ${VAR} interpolation intact.
esc() { printf '%s' "${1:-}" | sed 's/\$/\$\$/g'; }

# Read existing .env literally (never `source` — $$-escaped values would be
# expanded by the shell). Splits on the first '=', keeps the value verbatim.
declare -A CUR
if [[ -f "$ENV_FILE" ]]; then
  while IFS= read -r line || [[ -n "$line" ]]; do
    [[ "$line" =~ ^[[:space:]]*# ]] && continue
    [[ "$line" != *=* ]] && continue
    key="${line%%=*}"; key="${key//[[:space:]]/}"
    [[ -z "$key" ]] && continue
    CUR["$key"]="${line#*=}"
  done < "$ENV_FILE"
fi
cur() { printf '%s' "${CUR[$1]:-}"; }

declare -A OUT
set_raw()   { OUT["$1"]="$2"; }                # value already final/escaped
set_plain() { OUT["$1"]="$(esc "$2")"; }       # escape a plain value

# Keys we manage explicitly; anything else in an existing .env is preserved
# verbatim (see the writer). Populated as resolve*/set_* record a key.
declare -A KNOWN

# resolve KEY "prompt" "default"
#   Existing value  -> kept verbatim (already $$-escaped; NOT re-escaped).
#   Missing value   -> prompt (or --yes default), then escape once.
# Sets OUT[KEY] AND the global RESOLVED (the plain-ish value) so callers can derive
# later defaults from it. MUST run in the parent shell (never `$(resolve …)`, which
# would strand OUT/KNOWN in a subshell) — read RESOLVED instead.
RESOLVED=""
resolve() {
  local key="$1" prompt="$2" def="${3:-}"
  KNOWN["$key"]=1
  if [[ -n "${CUR[$key]:-}" ]]; then
    RESOLVED="${CUR[$key]}"; OUT["$key"]="$RESOLVED"
  else
    RESOLVED="$(ask "$prompt" "$def")"; OUT["$key"]="$(esc "$RESOLVED")"
  fi
}

# resolve_gen KEY generator-command...   (generator only runs if the key is missing)
resolve_gen() {
  local key="$1"; shift
  KNOWN["$key"]=1
  if [[ -n "${CUR[$key]:-}" ]]; then OUT["$key"]="${CUR[$key]}"; else OUT["$key"]="$(esc "$("$@")")"; fi
}

# Prompt with a default (reads from the real terminal so redirected stdin is ok).
# Honours --yes by returning the default without prompting.
ask() {
  local prompt="$1" def="${2:-}" ans
  if [[ $ASSUME_YES -eq 1 ]]; then printf '%s' "$def"; return; fi
  if [[ -n "$def" ]]; then
    read -r -p "$prompt [$def]: " ans </dev/tty || ans=""
    printf '%s' "${ans:-$def}"
  else
    read -r -p "$prompt: " ans </dev/tty || ans=""
    printf '%s' "$ans"
  fi
}

ask_yn() { # ask_yn "prompt" default(y/n) -> echoes y or n
  local prompt="$1" def="${2:-y}" ans
  if [[ $ASSUME_YES -eq 1 ]]; then printf '%s' "$def"; return; fi
  read -r -p "$prompt [$( [[ $def == y ]] && echo 'Y/n' || echo 'y/N' )]: " ans </dev/tty || ans=""
  ans="${ans:-$def}"
  case "$ans" in [Yy]*) echo y ;; *) echo n ;; esac
}

gen_secret_key() { openssl rand -base64 64 | tr -d '\n'; }        # >=64 chars, no '$'
gen_hmac()       { openssl rand -hex 32; }                        # 64 hex chars
gen_db_password(){ openssl rand -base64 48 | tr -dc 'A-Za-z0-9' | head -c 32; }  # URL-safe

# VAPID P-256 keypair -> sets VAPID_PUB / VAPID_PRIV (base64url, unpadded).
VAPID_PUB=""; VAPID_PRIV=""
gen_vapid() {
  local pem="$TMP/vapid.pem"
  openssl ecparam -name prime256v1 -genkey -noout -out "$pem" 2>/dev/null
  VAPID_PUB="$(openssl ec -in "$pem" -pubout -outform DER 2>/dev/null | tail -c 65 | openssl base64 -A | tr '+/' '-_' | tr -d '=')"
  VAPID_PRIV="$(openssl ec -in "$pem" -outform DER 2>/dev/null | tail -c +8 | head -c 32 | openssl base64 -A | tr '+/' '-_' | tr -d '=')"
}

# bcrypt htpasswd entry "user:hash" — prefer local htpasswd, fall back to Docker.
gen_htpasswd() {
  local u="$1" p="$2"
  if command -v htpasswd >/dev/null 2>&1; then
    htpasswd -nbB "$u" "$p"
  elif command -v docker >/dev/null 2>&1; then
    docker run --rm httpd:2-alpine htpasswd -nbB "$u" "$p"
  else
    echo "setup.sh: need 'htpasswd' or 'docker' to hash the Basic-Auth password." >&2
    return 1
  fi
}

# --- mode & derived defaults -------------------------------------------------

if [[ -z "$MODE" ]]; then
  MODE="$(ask "Deploy mode (beta/prod)" "beta")"
fi
[[ "$MODE" == "beta" || "$MODE" == "prod" ]] || { echo "setup.sh: mode must be beta or prod" >&2; exit 2; }

if [[ "$MODE" == "beta" ]]; then
  def_image="ghcr.io/buterland-beckerhook/app:beta"
  def_host="beta.buterland-beckerhook.de"
  def_tname="bb-beta"
  def_stack="bbh-beta"
  auth_default="y"
else
  def_image="ghcr.io/buterland-beckerhook/app:beta"   # prompt to pin a :sha-XXXX
  def_host="buterland-beckerhook.de"
  def_tname="bb"
  def_stack="bbh-prod"
  auth_default="n"
fi

# --- resolve each variable (existing wins; else prompt/generate) -------------
# Preserved values are written verbatim (already $$-escaped); only fresh values
# are escaped — see resolve()/resolve_gen(). This avoids re-escaping a $-bearing
# value (e.g. an SMTP password) on every re-run.

# Deploy target
# STACK_NAME is the Compose project name (and thus the named-volume prefix), so
# Beta and Prod coexist on one host without sharing data. See compose.yml.
resolve STACK_NAME "Compose stack/project name" "$def_stack"
resolve IMAGE "Container image (pin :sha-XXXX for prod)" "$def_image"
resolve PHX_HOST "Public hostname (PHX_HOST)" "$def_host";      PHX_HOST="$RESOLVED"
resolve TRAEFIK_NAME "Traefik router/service name" "$def_tname"; TRAEFIK_NAME="$RESOLVED"

# Traefik host rule (Traefik v2 syntax; backticks are literal in .env).
if [[ "$MODE" == "beta" ]]; then
  def_rule="Host(\`$PHX_HOST\`)"
else
  def_rule="Host(\`$PHX_HOST\`, \`www.$PHX_HOST\`)"
fi
resolve TRAEFIK_RULE "Traefik host rule" "$def_rule"

# Basic-Auth (managed here so the middleware chain and the hash stay consistent).
GENERATED_AUTH_PW=""
KNOWN[BASIC_AUTH_USERS]=1; KNOWN[TRAEFIK_MIDDLEWARES]=1
BASIC_AUTH_USERS_RAW="$(cur BASIC_AUTH_USERS)"        # may be empty
MW_EXISTING="${CUR[TRAEFIK_MIDDLEWARES]:-}"
if [[ -n "$MW_EXISTING" ]]; then
  # Preserve a prior, deliberate choice (chain + hash) verbatim.
  set_raw TRAEFIK_MIDDLEWARES "$MW_EXISTING"
  set_raw BASIC_AUTH_USERS "$BASIC_AUTH_USERS_RAW"
else
  auth_on="$(ask_yn "Protect the site with Basic-Auth?" "$auth_default")"
  if [[ "$auth_on" == "y" ]]; then
    au="$(ask "Basic-Auth username" "beta")"
    if [[ $ASSUME_YES -eq 1 ]]; then
      ap="$(openssl rand -base64 18 | tr -dc 'A-Za-z0-9' | head -c 20)"; GENERATED_AUTH_PW="$ap"
    else
      read -rs -p "Basic-Auth password [generate]: " ap </dev/tty || ap=""; echo
      if [[ -z "$ap" ]]; then ap="$(openssl rand -base64 18 | tr -dc 'A-Za-z0-9' | head -c 20)"; GENERATED_AUTH_PW="$ap"; fi
    fi
    hash_line="$(gen_htpasswd "$au" "$ap")"
    set_plain BASIC_AUTH_USERS "$hash_line"           # esc() doubles the bcrypt '$'
    if [[ "$MODE" == "beta" ]]; then
      set_plain TRAEFIK_MIDDLEWARES "${TRAEFIK_NAME}-compress,${TRAEFIK_NAME}-auth,${TRAEFIK_NAME}-noindex"
    else
      set_plain TRAEFIK_MIDDLEWARES "${TRAEFIK_NAME}-compress,${TRAEFIK_NAME}-auth,${TRAEFIK_NAME}-www"
    fi
  else
    set_raw BASIC_AUTH_USERS ""                        # empty & unreferenced -> harmless
    if [[ "$MODE" == "beta" ]]; then
      set_plain TRAEFIK_MIDDLEWARES "${TRAEFIK_NAME}-compress,${TRAEFIK_NAME}-noindex"
    else
      set_plain TRAEFIK_MIDDLEWARES "${TRAEFIK_NAME}-compress,${TRAEFIK_NAME}-www"
    fi
  fi
fi

# Database
resolve DB_USER "Database user" "bbh"
resolve_gen DB_PASSWORD gen_db_password

# Phoenix secret
resolve_gen SECRET_KEY_BASE gen_secret_key

# Web Push (VAPID) — regenerate as a pair if either half is missing.
KNOWN[VAPID_PUBLIC_KEY]=1; KNOWN[VAPID_PRIVATE_KEY]=1
if [[ -n "${CUR[VAPID_PUBLIC_KEY]:-}" && -n "${CUR[VAPID_PRIVATE_KEY]:-}" ]]; then
  set_raw VAPID_PUBLIC_KEY "${CUR[VAPID_PUBLIC_KEY]}"; set_raw VAPID_PRIVATE_KEY "${CUR[VAPID_PRIVATE_KEY]}"
else
  gen_vapid; set_plain VAPID_PUBLIC_KEY "$VAPID_PUB"; set_plain VAPID_PRIVATE_KEY "$VAPID_PRIV"
fi
resolve VAPID_SUBJECT "VAPID subject (mailto:)" "mailto:admin@buterland-beckerhook.de"

# Contact form spam protection
resolve_gen ALTCHA_HMAC_KEY gen_hmac

# SMTP + contact addresses (optional; preserved if already set).
# No relay host -> no outbound mail, so don't bother asking for port/user/password.
resolve SMTP_RELAY "SMTP relay host (blank to skip)" ""; smtp_relay_val="$RESOLVED"
KNOWN[SMTP_PORT]=1; KNOWN[SMTP_USERNAME]=1; KNOWN[SMTP_PASSWORD]=1
if [[ -n "$smtp_relay_val" ]]; then
  resolve SMTP_PORT     "SMTP port" "587"
  resolve SMTP_USERNAME "SMTP username (blank to skip)" ""
  if [[ -n "${CUR[SMTP_PASSWORD]:-}" ]]; then
    set_raw SMTP_PASSWORD "${CUR[SMTP_PASSWORD]}"        # preserved: already escaped
  else
    smtp_pw=""
    [[ $ASSUME_YES -eq 0 ]] && { read -rs -p "SMTP password (blank to skip): " smtp_pw </dev/tty || smtp_pw=""; echo; }
    set_plain SMTP_PASSWORD "$smtp_pw"
  fi
else
  # Keep any existing values (already escaped); otherwise harmless defaults.
  OUT[SMTP_PORT]="${CUR[SMTP_PORT]:-587}"
  OUT[SMTP_USERNAME]="${CUR[SMTP_USERNAME]:-}"
  OUT[SMTP_PASSWORD]="${CUR[SMTP_PASSWORD]:-}"
fi
resolve CONTACT_RECIPIENT   "Contact recipient"   "info@buterland-beckerhook.de"
resolve CONTACT_SENDER      "Contact sender"      "noreply@buterland-beckerhook.de"
resolve CONTACT_SENDER_NAME "Contact sender name" "Buterland-Beckerhook.de"

# Matomo (optional). No URL -> analytics disabled, so don't ask for the site id.
resolve MATOMO_URL "Matomo URL (blank to disable)" ""; matomo_url_val="$RESOLVED"
KNOWN[MATOMO_SITE_ID]=1
if [[ -n "$matomo_url_val" ]]; then
  resolve MATOMO_SITE_ID "Matomo site id (blank to disable)" ""
else
  OUT[MATOMO_SITE_ID]="${CUR[MATOMO_SITE_ID]:-}"
fi

# Logging. Not prompted (info suits both modes); operators flip it to debug in
# .env when diagnosing. Preserve an existing value verbatim (already escaped, like
# every other managed key); only a fresh default is escaped once.
KNOWN[LOG_LEVEL]=1
if [[ -n "${CUR[LOG_LEVEL]:-}" ]]; then
  set_raw   LOG_LEVEL "${CUR[LOG_LEVEL]}"
else
  set_plain LOG_LEVEL "info"
fi

# Time zone. Not prompted (Europe/Berlin suits the club); operators override it in
# .env. Preserve an existing value verbatim; only a fresh default is escaped once.
KNOWN[TIME_ZONE]=1
if [[ -n "${CUR[TIME_ZONE]:-}" ]]; then
  set_raw   TIME_ZONE "${CUR[TIME_ZONE]}"
else
  set_plain TIME_ZONE "Europe/Berlin"
fi

# --- write .env atomically ---------------------------------------------------
# Temp file sits next to $ENV_FILE so the final mv is a same-filesystem atomic
# rename (a /tmp temp could cross filesystems and degrade to copy-then-unlink).
umask 077
ENV_TMP="$(mktemp "$ENV_FILE.XXXXXX")"
{
  echo "# Generated by deploy/setup.sh — every value has \$ doubled to \$\$ so it"
  echo "# survives Docker Compose \${VAR} interpolation. Re-run setup.sh to fill gaps."
  echo "# DATABASE_URL is assembled by compose.yml from DB_USER/DB_PASSWORD."
  echo
  echo "# --- Deploy target ---"
  for k in STACK_NAME IMAGE PHX_HOST; do printf '%s=%s\n' "$k" "${OUT[$k]}"; done
  echo
  echo "# --- Traefik routing ---"
  for k in TRAEFIK_NAME TRAEFIK_RULE TRAEFIK_MIDDLEWARES BASIC_AUTH_USERS; do printf '%s=%s\n' "$k" "${OUT[$k]}"; done
  echo
  echo "# --- Database ---"
  for k in DB_USER DB_PASSWORD; do printf '%s=%s\n' "$k" "${OUT[$k]}"; done
  echo
  echo "# --- Phoenix ---"
  printf 'SECRET_KEY_BASE=%s\n' "${OUT[SECRET_KEY_BASE]}"
  echo
  echo "# --- Web Push (VAPID) ---"
  for k in VAPID_PUBLIC_KEY VAPID_PRIVATE_KEY VAPID_SUBJECT; do printf '%s=%s\n' "$k" "${OUT[$k]}"; done
  echo
  echo "# --- Contact form (Altcha + SMTP) ---"
  for k in ALTCHA_HMAC_KEY SMTP_RELAY SMTP_PORT SMTP_USERNAME SMTP_PASSWORD CONTACT_RECIPIENT CONTACT_SENDER CONTACT_SENDER_NAME; do
    printf '%s=%s\n' "$k" "${OUT[$k]}"
  done
  echo
  echo "# --- Matomo (optional) ---"
  for k in MATOMO_URL MATOMO_SITE_ID; do printf '%s=%s\n' "$k" "${OUT[$k]}"; done
  echo
  echo "# --- Logging ---"
  printf 'LOG_LEVEL=%s\n' "${OUT[LOG_LEVEL]}"
  echo
  echo "# --- Time zone ---"
  printf 'TIME_ZONE=%s\n' "${OUT[TIME_ZONE]}"
  # Pass through any operator-added keys we don't manage, so re-running never
  # silently drops them (values are already $$-escaped on disk — write verbatim).
  extra=""
  for k in "${!CUR[@]}"; do [[ -n "${KNOWN[$k]:-}" ]] || extra+="$k"$'\n'; done
  if [[ -n "$extra" ]]; then
    echo
    echo "# --- Preserved (operator-added; not managed by setup.sh) ---"
    while IFS= read -r k; do [[ -n "$k" ]] && printf '%s=%s\n' "$k" "${CUR[$k]}"; done \
      < <(printf '%s' "$extra" | sort)
  fi
} > "$ENV_TMP"
mv "$ENV_TMP" "$ENV_FILE"
ENV_TMP=""
chmod 600 "$ENV_FILE"

echo
echo "Wrote $ENV_FILE (mode: $MODE)."

# --- self-check: compose must render, and the auth hash must not be truncated -
if command -v docker >/dev/null 2>&1; then
  if ( cd "$SCRIPT_DIR" && docker compose --env-file "$ENV_FILE" -f "$COMPOSE_FILE" config >/dev/null 2>"$TMP/cfg.err" ); then
    echo "Self-check: 'docker compose config' renders cleanly."
    if [[ -n "${OUT[BASIC_AUTH_USERS]}" ]]; then
      rendered="$(cd "$SCRIPT_DIR" && docker compose --env-file "$ENV_FILE" -f "$COMPOSE_FILE" config 2>/dev/null | grep -m1 'basicauth.users' || true)"
      # A bcrypt htpasswd entry is ~60 chars; if interpolation had truncated it the
      # rendered value would be far shorter than the source.
      if [[ ${#rendered} -lt 40 ]]; then
        echo "Self-check WARNING: rendered Basic-Auth value looks truncated:" >&2
        echo "  $rendered" >&2
      else
        echo "Self-check: Basic-Auth hash survived interpolation intact."
      fi
    fi
  else
    echo "Self-check WARNING: 'docker compose config' failed:" >&2
    sed 's/^/  /' "$TMP/cfg.err" >&2
  fi
else
  echo "Self-check skipped (docker not found on PATH)."
fi

if [[ -n "$GENERATED_AUTH_PW" ]]; then
  echo
  echo "==================================================================="
  echo " Basic-Auth password (shown once — save it now):"
  echo "     $GENERATED_AUTH_PW"
  echo "==================================================================="
fi

echo
echo "Next: docker compose --env-file .env up -d"
