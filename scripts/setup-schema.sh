#!/usr/bin/env bash
# =============================================================================
# Directus Schema Setup
# Creates all collections, fields, and relations for buterland-beckerhook.de
#
# Usage:
#   ./scripts/setup-schema.sh [DIRECTUS_URL] [ADMIN_EMAIL] [ADMIN_PASSWORD]
#
# Defaults:
#   DIRECTUS_URL=http://localhost:8055
#   ADMIN_EMAIL / ADMIN_PASSWORD from .env or arguments
# =============================================================================

set -euo pipefail

DIRECTUS_URL="${1:-http://localhost:8055}"
ADMIN_EMAIL="${2:-${ADMIN_EMAIL:-admin@buterland-beckerhook.de}}"
ADMIN_PASSWORD="${3:-${ADMIN_PASSWORD:-directus}}"

echo "=== Directus Schema Setup ==="
echo "URL: $DIRECTUS_URL"
echo "Admin: $ADMIN_EMAIL"
echo ""

# --- Authenticate ---
echo "Authenticating..."
AUTH_RESPONSE=$(curl -sf "$DIRECTUS_URL/auth/login" \
  -H 'Content-Type: application/json' \
  -d "{\"email\":\"$ADMIN_EMAIL\",\"password\":\"$ADMIN_PASSWORD\"}")
TOKEN=$(echo "$AUTH_RESPONSE" | python3 -c "import sys,json; print(json.load(sys.stdin)['data']['access_token'])")
echo "Got access token."

# Helper: POST to Directus API
api_post() {
  local endpoint="$1"
  local data="$2"
  local response
  response=$(curl -sf "$DIRECTUS_URL$endpoint" \
    -H "Authorization: Bearer $TOKEN" \
    -H 'Content-Type: application/json' \
    -d "$data" 2>&1) || {
    echo "  WARN: $endpoint may already exist or failed"
    return 0
  }
  echo "  OK: $endpoint"
}

# Helper: PATCH to Directus API
api_patch() {
  local endpoint="$1"
  local data="$2"
  curl -sf -X PATCH "$DIRECTUS_URL$endpoint" \
    -H "Authorization: Bearer $TOKEN" \
    -H 'Content-Type: application/json' \
    -d "$data" > /dev/null 2>&1 || true
}

# =============================================================================
# 1. COLLECTIONS
# =============================================================================
echo ""
echo "--- Creating Collections ---"

# locations (no dependencies)
api_post "/collections" '{
  "collection": "locations",
  "meta": {
    "icon": "place",
    "note": "Veranstaltungsorte",
    "sort_field": "name",
    "archive_field": null,
    "archive_value": null,
    "unarchive_value": null,
    "translations": [{"language": "de-DE", "translation": "Orte"}]
  },
  "schema": {},
  "fields": [
    {"field": "id", "type": "uuid", "meta": {"hidden": true, "interface": "input", "readonly": true, "special": ["uuid"]}, "schema": {"is_primary_key": true, "has_auto_increment": false}},
    {"field": "key", "type": "string", "meta": {"interface": "input", "required": true, "note": "Eindeutiger Schlüssel (z.B. platz, dinkelhof)"}, "schema": {"is_unique": true, "is_nullable": false}},
    {"field": "name", "type": "string", "meta": {"interface": "input", "required": true, "note": "Anzeigename"}, "schema": {"is_nullable": false}},
    {"field": "street", "type": "string", "meta": {"interface": "input"}, "schema": {"is_nullable": true}},
    {"field": "zip", "type": "string", "meta": {"interface": "input"}, "schema": {"is_nullable": true}},
    {"field": "city", "type": "string", "meta": {"interface": "input"}, "schema": {"is_nullable": true}},
    {"field": "lat", "type": "float", "meta": {"interface": "input", "note": "GPS Breitengrad"}, "schema": {"is_nullable": true}},
    {"field": "lng", "type": "float", "meta": {"interface": "input", "note": "GPS Längengrad"}, "schema": {"is_nullable": true}},
    {"field": "url", "type": "string", "meta": {"interface": "input", "note": "Website-URL (z.B. Homepage des Ortes)"}, "schema": {"is_nullable": true}},
    {"field": "maps_url", "type": "string", "meta": {"interface": "input", "note": "Google Maps Link"}, "schema": {"is_nullable": true}}
  ]
}'

# people
api_post "/collections" '{
  "collection": "people",
  "meta": {
    "icon": "groups",
    "note": "Vorstand und Offiziere",
    "sort_field": "sort_order",
    "translations": [{"language": "de-DE", "translation": "Personen"}]
  },
  "schema": {},
  "fields": [
    {"field": "id", "type": "uuid", "meta": {"hidden": true, "interface": "input", "readonly": true, "special": ["uuid"]}, "schema": {"is_primary_key": true, "has_auto_increment": false}},
    {"field": "group", "type": "string", "meta": {"interface": "select-dropdown", "required": true, "options": {"choices": [{"text": "Vorstand", "value": "vorstand"}, {"text": "Offiziere", "value": "offiziere"}]}}, "schema": {"is_nullable": false}},
    {"field": "role", "type": "string", "meta": {"interface": "input", "required": true, "note": "z.B. Präsident, Oberst"}, "schema": {"is_nullable": false}},
    {"field": "role_key", "type": "string", "meta": {"interface": "input", "required": true, "note": "z.B. praesident, oberst (für Sortierung)"}, "schema": {"is_nullable": false}},
    {"field": "name", "type": "string", "meta": {"interface": "input", "required": true}, "schema": {"is_nullable": false}},
    {"field": "street", "type": "string", "meta": {"interface": "input"}, "schema": {"is_nullable": true}},
    {"field": "city", "type": "string", "meta": {"interface": "input"}, "schema": {"is_nullable": true}},
    {"field": "sort_order", "type": "integer", "meta": {"interface": "input", "required": true}, "schema": {"is_nullable": false, "default_value": 0}}
  ]
}'

# pages
api_post "/collections" '{
  "collection": "pages",
  "meta": {
    "icon": "article",
    "note": "Statische Seiten (Impressum, Datenschutz, Verein-Unterseiten)",
    "sort_field": "sort_order",
    "archive_field": "status",
    "archive_value": "archived",
    "unarchive_value": "draft",
    "translations": [{"language": "de-DE", "translation": "Seiten"}]
  },
  "schema": {},
  "fields": [
    {"field": "id", "type": "uuid", "meta": {"hidden": true, "interface": "input", "readonly": true, "special": ["uuid"]}, "schema": {"is_primary_key": true, "has_auto_increment": false}},
    {"field": "status", "type": "string", "meta": {"interface": "select-dropdown", "required": true, "options": {"choices": [{"text": "Entwurf", "value": "draft"}, {"text": "Veröffentlicht", "value": "published"}]}, "default_value": "draft", "width": "half"}, "schema": {"is_nullable": false, "default_value": "draft"}},
    {"field": "title", "type": "string", "meta": {"interface": "input", "required": true, "width": "half"}, "schema": {"is_nullable": false}},
    {"field": "slug", "type": "string", "meta": {"interface": "input", "required": true, "note": "URL-Pfad (z.B. impressum, ueber-uns)", "options": {"slug": true}}, "schema": {"is_unique": true, "is_nullable": false}},
    {"field": "body", "type": "text", "meta": {"interface": "input-rich-text-html", "required": true, "note": "Seiteninhalt"}, "schema": {"is_nullable": false}},
    {"field": "sort_order", "type": "integer", "meta": {"interface": "input", "width": "half"}, "schema": {"is_nullable": true, "default_value": 0}}
  ]
}'

# articles (without relations first — those come after thrones exists)
api_post "/collections" '{
  "collection": "articles",
  "meta": {
    "icon": "newspaper",
    "note": "Artikel und Neuigkeiten",
    "sort_field": null,
    "archive_field": "status",
    "archive_value": "archived",
    "unarchive_value": "draft",
    "translations": [{"language": "de-DE", "translation": "Artikel"}]
  },
  "schema": {},
  "fields": [
    {"field": "id", "type": "uuid", "meta": {"hidden": true, "interface": "input", "readonly": true, "special": ["uuid"]}, "schema": {"is_primary_key": true, "has_auto_increment": false}},
    {"field": "status", "type": "string", "meta": {"interface": "select-dropdown", "required": true, "options": {"choices": [{"text": "Entwurf", "value": "draft"}, {"text": "Veröffentlicht", "value": "published"}, {"text": "Archiviert", "value": "archived"}]}, "default_value": "draft", "width": "half"}, "schema": {"is_nullable": false, "default_value": "draft"}},
    {"field": "title", "type": "string", "meta": {"interface": "input", "required": true}, "schema": {"is_nullable": false}},
    {"field": "subtitle", "type": "string", "meta": {"interface": "input"}, "schema": {"is_nullable": true}},
    {"field": "slug", "type": "string", "meta": {"interface": "input", "required": true, "options": {"slug": true}}, "schema": {"is_unique": true, "is_nullable": false}},
    {"field": "date_published", "type": "timestamp", "meta": {"interface": "datetime", "required": true, "width": "half"}, "schema": {"is_nullable": false}},
    {"field": "author", "type": "string", "meta": {"interface": "input", "width": "half"}, "schema": {"is_nullable": true}},
    {"field": "tags", "type": "json", "meta": {"interface": "tags", "special": ["cast-json"], "note": "z.B. Thron, Schützenfest"}, "schema": {"is_nullable": true}},
    {"field": "body", "type": "text", "meta": {"interface": "input-rich-text-html", "note": "Artikeltext"}, "schema": {"is_nullable": true}},
    {"field": "no_article", "type": "boolean", "meta": {"interface": "boolean", "width": "half", "note": "Nur Thron-Anzeige, kein eigener Artikel"}, "schema": {"is_nullable": false, "default_value": false}},
    {"field": "aliases", "type": "json", "meta": {"interface": "tags", "special": ["cast-json"], "note": "Alte URLs für Redirects"}, "schema": {"is_nullable": true}}
  ]
}'

# article_images
api_post "/collections" '{
  "collection": "article_images",
  "meta": {
    "icon": "photo_library",
    "note": "Bilder zu Artikeln",
    "sort_field": "sort",
    "translations": [{"language": "de-DE", "translation": "Artikelbilder"}],
    "hidden": true
  },
  "schema": {},
  "fields": [
    {"field": "id", "type": "uuid", "meta": {"hidden": true, "interface": "input", "readonly": true, "special": ["uuid"]}, "schema": {"is_primary_key": true, "has_auto_increment": false}},
    {"field": "logical_name", "type": "string", "meta": {"interface": "input", "note": "z.B. thron-1, bild-1"}, "schema": {"is_nullable": true}},
    {"field": "title", "type": "string", "meta": {"interface": "input", "note": "Bildunterschrift"}, "schema": {"is_nullable": true}},
    {"field": "copyright", "type": "string", "meta": {"interface": "input", "note": "Urheber"}, "schema": {"is_nullable": true}},
    {"field": "sort", "type": "integer", "meta": {"interface": "input", "hidden": true}, "schema": {"is_nullable": true}},
    {"field": "use_as_throne_picture", "type": "boolean", "meta": {"interface": "boolean", "note": "Als Thron-Bild verwenden?"}, "schema": {"is_nullable": false, "default_value": false}}
  ]
}'

# thrones
api_post "/collections" '{
  "collection": "thrones",
  "meta": {
    "icon": "emoji_events",
    "note": "Throne und Königspaare",
    "translations": [{"language": "de-DE", "translation": "Throne"}]
  },
  "schema": {},
  "fields": [
    {"field": "id", "type": "uuid", "meta": {"hidden": true, "interface": "input", "readonly": true, "special": ["uuid"]}, "schema": {"is_primary_key": true, "has_auto_increment": false}},
    {"field": "type", "type": "string", "meta": {"interface": "select-dropdown", "required": true, "width": "half", "options": {"choices": [{"text": "König", "value": "koenig"}, {"text": "Kaiser", "value": "kaiser"}, {"text": "Stadtkaiser", "value": "stadtkaiser"}]}}, "schema": {"is_nullable": false}},
    {"field": "begin", "type": "integer", "meta": {"interface": "input", "required": true, "width": "half", "note": "Startjahr (z.B. 2024)"}, "schema": {"is_nullable": false}},
    {"field": "end", "type": "integer", "meta": {"interface": "input", "width": "half", "note": "Endjahr (z.B. 2025), leer wenn noch regierend"}, "schema": {"is_nullable": true}},
    {"field": "king_title", "type": "string", "meta": {"interface": "input", "width": "half", "note": "Regalname: Gerd X., Bernhard I."}, "schema": {"is_nullable": true}},
    {"field": "king", "type": "string", "meta": {"interface": "input", "required": true, "width": "half", "note": "Bürgerlicher Name"}, "schema": {"is_nullable": false}},
    {"field": "queen", "type": "string", "meta": {"interface": "input", "required": true, "width": "half"}, "schema": {"is_nullable": false}},
    {"field": "moh1", "type": "string", "meta": {"interface": "input", "width": "half", "note": "Ehrendame 1"}, "schema": {"is_nullable": true}},
    {"field": "moh2", "type": "string", "meta": {"interface": "input", "width": "half", "note": "Ehrendame 2"}, "schema": {"is_nullable": true}},
    {"field": "loh1", "type": "string", "meta": {"interface": "input", "width": "half", "note": "Ehrenherr 1"}, "schema": {"is_nullable": true}},
    {"field": "loh2", "type": "string", "meta": {"interface": "input", "width": "half", "note": "Ehrenherr 2"}, "schema": {"is_nullable": true}},
    {"field": "cupbearer", "type": "string", "meta": {"interface": "input", "width": "half", "note": "Mundschenk"}, "schema": {"is_nullable": true}},
    {"field": "courtmarshal", "type": "string", "meta": {"interface": "input", "width": "half", "note": "Oberhofmarschall"}, "schema": {"is_nullable": true}}
  ]
}'

# events
api_post "/collections" '{
  "collection": "events",
  "meta": {
    "icon": "event",
    "note": "Termine und Veranstaltungen",
    "archive_field": "status",
    "archive_value": "canceled",
    "unarchive_value": "draft",
    "translations": [{"language": "de-DE", "translation": "Termine"}]
  },
  "schema": {},
  "fields": [
    {"field": "id", "type": "uuid", "meta": {"hidden": true, "interface": "input", "readonly": true, "special": ["uuid"]}, "schema": {"is_primary_key": true, "has_auto_increment": false}},
    {"field": "status", "type": "string", "meta": {"interface": "select-dropdown", "required": true, "options": {"choices": [{"text": "Entwurf", "value": "draft"}, {"text": "Veröffentlicht", "value": "published"}, {"text": "Abgesagt", "value": "canceled"}]}, "default_value": "draft", "width": "half"}, "schema": {"is_nullable": false, "default_value": "draft"}},
    {"field": "title", "type": "string", "meta": {"interface": "input", "required": true}, "schema": {"is_nullable": false}},
    {"field": "slug", "type": "string", "meta": {"interface": "input", "required": true, "options": {"slug": true}}, "schema": {"is_unique": true, "is_nullable": false}},
    {"field": "start", "type": "timestamp", "meta": {"interface": "datetime", "required": true, "width": "half"}, "schema": {"is_nullable": false}},
    {"field": "end", "type": "timestamp", "meta": {"interface": "datetime", "width": "half"}, "schema": {"is_nullable": true}},
    {"field": "body", "type": "text", "meta": {"interface": "input-rich-text-html"}, "schema": {"is_nullable": true}},
    {"field": "cancel_reason", "type": "string", "meta": {"interface": "input", "note": "Grund bei Absage"}, "schema": {"is_nullable": true}},
    {"field": "announce", "type": "boolean", "meta": {"interface": "boolean", "width": "half", "note": "Öffentlich ankündigen"}, "schema": {"is_nullable": false, "default_value": true}},
    {"field": "revision", "type": "integer", "meta": {"interface": "input", "width": "half"}, "schema": {"is_nullable": true}},
    {"field": "enable_ical", "type": "boolean", "meta": {"interface": "boolean", "width": "half", "note": "iCal-Export aktivieren"}, "schema": {"is_nullable": false, "default_value": true}}
  ]
}'

echo ""
echo "--- Creating Relations ---"

# =============================================================================
# 2. RELATIONS (after all collections exist)
# =============================================================================

# pages.parent → pages (self-referencing M2O)
api_post "/fields/pages" '{
  "field": "parent",
  "type": "uuid",
  "meta": {"interface": "select-dropdown-m2o", "special": ["m2o"], "note": "Übergeordnete Seite"},
  "schema": {"is_nullable": true}
}'
api_post "/relations" '{
  "collection": "pages",
  "field": "parent",
  "related_collection": "pages",
  "meta": {"one_field": null, "sort_field": null}
}'

# article_images.article → articles (M2O)
api_post "/fields/article_images" '{
  "field": "article",
  "type": "uuid",
  "meta": {"interface": "select-dropdown-m2o", "special": ["m2o"], "required": true, "hidden": true},
  "schema": {"is_nullable": false}
}'
api_post "/relations" '{
  "collection": "article_images",
  "field": "article",
  "related_collection": "articles",
  "meta": {"one_field": "images", "sort_field": "sort", "one_deselect_action": "delete"}
}'

# article_images.image → directus_files (M2O file)
api_post "/fields/article_images" '{
  "field": "image",
  "type": "uuid",
  "meta": {"interface": "file-image", "special": ["file"], "required": true},
  "schema": {"is_nullable": false}
}'
api_post "/relations" '{
  "collection": "article_images",
  "field": "image",
  "related_collection": "directus_files"
}'

# Patch the auto-created articles.images alias to set O2M interface options
api_patch "/fields/articles/images" '{
  "meta": {"interface": "list-o2m", "special": ["o2m"], "note": "Zugehörige Bilder", "options": {"template": "{{title}} ({{logical_name}})"}}
}'

# thrones.article → articles (M2O, effectively O2O)
api_post "/fields/thrones" '{
  "field": "article",
  "type": "uuid",
  "meta": {"interface": "select-dropdown-m2o", "special": ["m2o"], "required": true, "note": "Zugehöriger Artikel"},
  "schema": {"is_nullable": false}
}'
api_post "/relations" '{
  "collection": "thrones",
  "field": "article",
  "related_collection": "articles",
  "meta": {"one_field": "throne", "one_deselect_action": "nullify"}
}'

# Patch the auto-created articles.throne alias to set O2M interface options
api_patch "/fields/articles/throne" '{
  "meta": {"interface": "list-o2m", "special": ["o2m"], "note": "Thron-Daten (wenn Thron-Artikel)", "options": {"enableCreate": true, "enableSelect": false, "limit": 1}}
}'

# events.location → locations (M2O)
api_post "/fields/events" '{
  "field": "location",
  "type": "uuid",
  "meta": {"interface": "select-dropdown-m2o", "special": ["m2o"], "note": "Veranstaltungsort", "display": "related-values", "display_options": {"template": "{{name}}"}},
  "schema": {"is_nullable": true}
}'
api_post "/relations" '{
  "collection": "events",
  "field": "location",
  "related_collection": "locations",
  "meta": {"one_field": null, "sort_field": null}
}'

echo ""
echo "=== Schema setup complete! ==="
echo ""
echo "Next steps:"
echo "  1. Configure a static token for API access"
echo "  2. Set up public read permissions"
echo "  3. Import seed data"
