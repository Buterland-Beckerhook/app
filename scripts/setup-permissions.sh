#!/usr/bin/env bash
# =============================================================================
# Directus Permissions & Token Setup
# Creates a static token for the admin user and sets up public read access.
#
# Usage:
#   ./scripts/setup-permissions.sh [DIRECTUS_URL] [ADMIN_EMAIL] [ADMIN_PASSWORD]
# =============================================================================

set -euo pipefail

DIRECTUS_URL="${1:-http://localhost:8055}"
ADMIN_EMAIL="${2:-${ADMIN_EMAIL:-admin@buterland-beckerhook.de}}"
ADMIN_PASSWORD="${3:-${ADMIN_PASSWORD:-directus}}"
STATIC_TOKEN="${DIRECTUS_STATIC_TOKEN:-dev-static-token-change-in-production}"

echo "=== Directus Permissions & Token Setup ==="
echo "URL: $DIRECTUS_URL"
echo ""

# --- Authenticate ---
echo "Authenticating..."
AUTH_RESPONSE=$(curl -sf "$DIRECTUS_URL/auth/login" \
  -H 'Content-Type: application/json' \
  -d "{\"email\":\"$ADMIN_EMAIL\",\"password\":\"$ADMIN_PASSWORD\"}")
TOKEN=$(echo "$AUTH_RESPONSE" | python3 -c "import sys,json; print(json.load(sys.stdin)['data']['access_token'])")
echo "Got access token."

# Helper
api_post() {
  local endpoint="$1"
  local data="$2"
  curl -sf "$DIRECTUS_URL$endpoint" \
    -H "Authorization: Bearer $TOKEN" \
    -H 'Content-Type: application/json' \
    -d "$data" > /dev/null 2>&1 || {
    echo "  WARN: $endpoint may already exist or failed"
    return 0
  }
  echo "  OK: $endpoint"
}

api_patch() {
  local endpoint="$1"
  local data="$2"
  curl -sf -X PATCH "$DIRECTUS_URL$endpoint" \
    -H "Authorization: Bearer $TOKEN" \
    -H 'Content-Type: application/json' \
    -d "$data" > /dev/null 2>&1 || {
    echo "  WARN: PATCH $endpoint failed"
    return 0
  }
  echo "  OK: PATCH $endpoint"
}

# =============================================================================
# 1. Set static token on admin user
# =============================================================================
echo ""
echo "--- Setting Static Token ---"

# Get admin user ID
ADMIN_ID=$(curl -sf "$DIRECTUS_URL/users/me" \
  -H "Authorization: Bearer $TOKEN" | python3 -c "import sys,json; print(json.load(sys.stdin)['data']['id'])")
echo "Admin user ID: $ADMIN_ID"

api_patch "/users/$ADMIN_ID" "{\"token\": \"$STATIC_TOKEN\"}"
echo "Static token set: $STATIC_TOKEN"

# Verify token works
echo -n "Verifying static token... "
HEALTH=$(curl -sf "$DIRECTUS_URL/users/me" -H "Authorization: Bearer $STATIC_TOKEN" | python3 -c "import sys,json; print(json.load(sys.stdin)['data']['email'])" 2>/dev/null || echo "FAILED")
echo "$HEALTH"

# =============================================================================
# 2. Public role permissions (read access to published content)
# =============================================================================
echo ""
echo "--- Setting up Public Permissions ---"

# The public role in Directus is identified by a null role.
# We need to find the public policy or create permissions directly.

# In Directus 11+, permissions are tied to policies.
# Let's find the public policy first.
PUBLIC_POLICY=$(curl -sf "$DIRECTUS_URL/policies" \
  -H "Authorization: Bearer $TOKEN" | python3 -c "
import sys, json
data = json.load(sys.stdin)['data']
for p in data:
    if p.get('admin_access') == False and 'public' in p.get('name','').lower():
        print(p['id'])
        break
" 2>/dev/null || echo "")

if [ -z "$PUBLIC_POLICY" ]; then
  echo "No public policy found — checking for public access role..."
  # In older Directus, public access uses a special role
  # Try to find it via the access entries
  PUBLIC_POLICY=$(curl -sf "$DIRECTUS_URL/policies" \
    -H "Authorization: Bearer $TOKEN" | python3 -c "
import sys, json
data = json.load(sys.stdin)['data']
for p in data:
    if p.get('admin_access') == False:
        print(p['id'])
        break
" 2>/dev/null || echo "")
fi

if [ -z "$PUBLIC_POLICY" ]; then
  echo "WARNING: Could not find public policy. Listing all policies..."
  curl -sf "$DIRECTUS_URL/policies" \
    -H "Authorization: Bearer $TOKEN" | python3 -m json.tool
  echo ""
  echo "You may need to set up public permissions manually in the Directus admin UI."
else
  echo "Public policy ID: $PUBLIC_POLICY"

  # Read-only permissions for public collections
  for COLLECTION in articles article_images thrones events locations people pages; do
    api_post "/permissions" "{
      \"policy\": \"$PUBLIC_POLICY\",
      \"collection\": \"$COLLECTION\",
      \"action\": \"read\",
      \"fields\": [\"*\"],
      \"permissions\": {},
      \"validation\": {}
    }"
  done

  # Also allow reading directus_files (for images)
  api_post "/permissions" "{
    \"policy\": \"$PUBLIC_POLICY\",
    \"collection\": \"directus_files\",
    \"action\": \"read\",
    \"fields\": [\"*\"],
    \"permissions\": {},
    \"validation\": {}
  }"
fi

echo ""
echo "=== Permissions setup complete! ==="
echo ""
echo "Static token for .env: DIRECTUS_STATIC_TOKEN=$STATIC_TOKEN"
echo "For dev frontend .env: DIRECTUS_URL=http://localhost:8055"
echo "                       DIRECTUS_TOKEN=$STATIC_TOKEN"
