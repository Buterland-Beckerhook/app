#!/usr/bin/env bash
# =============================================================================
# Directus Calendar Users Setup
# Creates 4 calendar users (Vorstand, Offiziere, Jungschützen, Kinderfest)
# with restricted permissions: can only create/edit internal events for their
# group, cannot set announce=true (i.e. cannot publish to Homepage).
#
# Usage:
#   ./scripts/setup-calendar-users.sh [DIRECTUS_URL] [ADMIN_EMAIL] [ADMIN_PASSWORD]
#
# Requires env vars (from .env):
#   CAL_VORSTAND_PASSWORD, CAL_OFFIZIERE_PASSWORD,
#   CAL_JUNGSCHUETZEN_PASSWORD, CAL_KINDERFEST_PASSWORD
# =============================================================================

set -euo pipefail

DIRECTUS_URL="${1:-http://localhost:8055}"
ADMIN_EMAIL="${2:-${ADMIN_EMAIL:-admin@buterland-beckerhook.de}}"
ADMIN_PASSWORD="${3:-${ADMIN_PASSWORD:-directus}}"

# Load calendar user passwords from env
CAL_VORSTAND_PASSWORD="${CAL_VORSTAND_PASSWORD:?Set CAL_VORSTAND_PASSWORD in .env}"
CAL_OFFIZIERE_PASSWORD="${CAL_OFFIZIERE_PASSWORD:?Set CAL_OFFIZIERE_PASSWORD in .env}"
CAL_JUNGSCHUETZEN_PASSWORD="${CAL_JUNGSCHUETZEN_PASSWORD:?Set CAL_JUNGSCHUETZEN_PASSWORD in .env}"
CAL_KINDERFEST_PASSWORD="${CAL_KINDERFEST_PASSWORD:?Set CAL_KINDERFEST_PASSWORD in .env}"

echo "=== Directus Calendar Users Setup ==="
echo "URL: $DIRECTUS_URL"
echo ""

# --- Authenticate ---
echo "Authenticating..."
AUTH_RESPONSE=$(curl -sf "$DIRECTUS_URL/auth/login" \
  -H 'Content-Type: application/json' \
  -d "{\"email\":\"$ADMIN_EMAIL\",\"password\":\"$ADMIN_PASSWORD\"}")
TOKEN=$(echo "$AUTH_RESPONSE" | python3 -c "import sys,json; print(json.load(sys.stdin)['data']['access_token'])")
echo "Got access token."

# Helpers
api_post() {
  local endpoint="$1"
  local data="$2"
  local response
  response=$(curl -sf "$DIRECTUS_URL$endpoint" \
    -H "Authorization: Bearer $TOKEN" \
    -H 'Content-Type: application/json' \
    -d "$data" 2>&1) || {
    echo "  WARN: $endpoint may already exist or failed"
    echo ""
    return 0
  }
  echo "  OK: $endpoint"
  echo "$response"
}

api_post_silent() {
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

# =============================================================================
# 1. Create "Kalender" role
# =============================================================================
echo ""
echo "--- Creating Calendar Role ---"

ROLE_RESPONSE=$(api_post "/roles" '{
  "name": "Kalender",
  "description": "Eingeschränkter Zugang: kann interne Termine anlegen und verwalten",
  "icon": "calendar_month",
  "admin_access": false,
  "app_access": true
}')

ROLE_ID=$(echo "$ROLE_RESPONSE" | python3 -c "
import sys, json
try:
    data = json.load(sys.stdin)
    print(data['data']['id'])
except:
    pass
" 2>/dev/null || echo "")

if [ -z "$ROLE_ID" ]; then
  echo "Role may already exist, looking it up..."
  ROLE_ID=$(curl -sf "$DIRECTUS_URL/roles" \
    -H "Authorization: Bearer $TOKEN" | python3 -c "
import sys, json
data = json.load(sys.stdin)['data']
for r in data:
    if r.get('name') == 'Kalender':
        print(r['id'])
        break
" 2>/dev/null || echo "")
fi

if [ -z "$ROLE_ID" ]; then
  echo "ERROR: Could not create or find 'Kalender' role."
  exit 1
fi

echo "Calendar role ID: $ROLE_ID"

# =============================================================================
# 2. Create policy with restricted event permissions
# =============================================================================
echo ""
echo "--- Creating Calendar Policy ---"

POLICY_RESPONSE=$(api_post "/policies" "{
  \"name\": \"Kalender-Bearbeiter\",
  \"description\": \"Kann interne Termine erstellen/bearbeiten, aber nicht öffentlich ankündigen\",
  \"icon\": \"edit_calendar\",
  \"admin_access\": false,
  \"app_access\": true
}")

POLICY_ID=$(echo "$POLICY_RESPONSE" | python3 -c "
import sys, json
try:
    data = json.load(sys.stdin)
    print(data['data']['id'])
except:
    pass
" 2>/dev/null || echo "")

if [ -z "$POLICY_ID" ]; then
  echo "Policy may already exist, looking it up..."
  POLICY_ID=$(curl -sf "$DIRECTUS_URL/policies" \
    -H "Authorization: Bearer $TOKEN" | python3 -c "
import sys, json
data = json.load(sys.stdin)['data']
for p in data:
    if p.get('name') == 'Kalender-Bearbeiter':
        print(p['id'])
        break
" 2>/dev/null || echo "")
fi

if [ -z "$POLICY_ID" ]; then
  echo "ERROR: Could not create or find 'Kalender-Bearbeiter' policy."
  exit 1
fi

echo "Calendar policy ID: $POLICY_ID"

# Attach policy to role
echo "Attaching policy to role..."
api_post_silent "/access" "{
  \"role\": \"$ROLE_ID\",
  \"policy\": \"$POLICY_ID\"
}"

# =============================================================================
# 3. Set permissions on the policy
# =============================================================================
echo ""
echo "--- Setting Calendar Permissions ---"

# events: CREATE — can create events, but announce is forced to false
# The 'presets' field sets default values that are applied on creation
# The 'fields' list controls which fields the user can write
api_post_silent "/permissions" "{
  \"policy\": \"$POLICY_ID\",
  \"collection\": \"events\",
  \"action\": \"create\",
  \"fields\": [\"title\", \"slug\", \"start\", \"end\", \"body\", \"cancel_reason\", \"status\", \"revision\", \"enable_ical\", \"location\", \"parent\", \"calendar\", \"announce\"],
  \"permissions\": {},
  \"validation\": {
    \"_and\": [
      {\"announce\": {\"_eq\": false}}
    ]
  },
  \"presets\": {
    \"announce\": false,
    \"status\": \"published\"
  }
}"

# events: READ — own events + all publicly announced events
api_post_silent "/permissions" "{
  \"policy\": \"$POLICY_ID\",
  \"collection\": \"events\",
  \"action\": \"read\",
  \"fields\": [\"*\"],
  \"permissions\": {
    \"_or\": [
      {\"user_created\": {\"_eq\": \"\$CURRENT_USER\"}},
      {\"announce\": {\"_eq\": true}}
    ]
  },
  \"validation\": {}
}"

# events: UPDATE — only own events, cannot change announce
api_post_silent "/permissions" "{
  \"policy\": \"$POLICY_ID\",
  \"collection\": \"events\",
  \"action\": \"update\",
  \"fields\": [\"title\", \"slug\", \"start\", \"end\", \"body\", \"cancel_reason\", \"status\", \"revision\", \"enable_ical\", \"location\", \"parent\", \"calendar\", \"announce\"],
  \"permissions\": {
    \"user_created\": {\"_eq\": \"\$CURRENT_USER\"}
  },
  \"validation\": {
    \"_and\": [
      {\"announce\": {\"_eq\": false}}
    ]
  }
}"

# events: DELETE — only own events
api_post_silent "/permissions" "{
  \"policy\": \"$POLICY_ID\",
  \"collection\": \"events\",
  \"action\": \"delete\",
  \"fields\": [\"*\"],
  \"permissions\": {
    \"user_created\": {\"_eq\": \"\$CURRENT_USER\"}
  },
  \"validation\": {}
}"

# locations: READ — need to see locations for the location dropdown
api_post_silent "/permissions" "{
  \"policy\": \"$POLICY_ID\",
  \"collection\": \"locations\",
  \"action\": \"read\",
  \"fields\": [\"*\"],
  \"permissions\": {},
  \"validation\": {}
}"

# directus_users: READ own profile (required for Directus app to work)
api_post_silent "/permissions" "{
  \"policy\": \"$POLICY_ID\",
  \"collection\": \"directus_users\",
  \"action\": \"read\",
  \"fields\": [\"id\", \"email\", \"first_name\", \"last_name\", \"avatar\", \"role\"],
  \"permissions\": {
    \"id\": {\"_eq\": \"\$CURRENT_USER\"}
  },
  \"validation\": {}
}"

# =============================================================================
# 4. Create the 4 calendar users
# =============================================================================
echo ""
echo "--- Creating Calendar Users ---"

create_calendar_user() {
  local email="$1"
  local first_name="$2"
  local password="$3"

  echo "Creating user: $email"
  api_post_silent "/users" "{
    \"email\": \"$email\",
    \"password\": \"$password\",
    \"first_name\": \"$first_name\",
    \"last_name\": \"Kalender\",
    \"role\": \"$ROLE_ID\",
    \"status\": \"active\"
  }"
}

create_calendar_user "vorstand@buterland-beckerhook.de" "Vorstand" "$CAL_VORSTAND_PASSWORD"
create_calendar_user "offiziere@buterland-beckerhook.de" "Offiziere" "$CAL_OFFIZIERE_PASSWORD"
create_calendar_user "jungschuetzen@buterland-beckerhook.de" "Jungschützen" "$CAL_JUNGSCHUETZEN_PASSWORD"
create_calendar_user "kinderfest@buterland-beckerhook.de" "Kinderfest" "$CAL_KINDERFEST_PASSWORD"

echo ""
echo "=== Calendar Users Setup Complete! ==="
echo ""
echo "Created 4 users with role 'Kalender':"
echo "  - vorstand@buterland-beckerhook.de"
echo "  - offiziere@buterland-beckerhook.de"
echo "  - jungschuetzen@buterland-beckerhook.de"
echo "  - kinderfest@buterland-beckerhook.de"
echo ""
echo "Permissions:"
echo "  - Can create/edit/delete own events (announce forced to false)"
echo "  - Can read own events + all publicly announced events"
echo "  - Can read locations (for dropdown)"
echo "  - Cannot set announce=true (enforced by validation)"
echo ""
echo "Later: iCal feeds at /api/ical/[calendar].ics + /api/ical/intern.ics"
