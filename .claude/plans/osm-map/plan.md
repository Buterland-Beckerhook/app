# Plan — OSM map for event locations (replace Google Maps links)

**Branch:** `feat/osm-map` (suggested) · **ADR:** write `docs/adr/0014-self-hosted-osm-map.md` in phase 2
**Scope:** 3 phases. Phase 1 is a standalone PR; phase 2 and 3 can ship together.

## Decisions locked in
- **No Google.** `Location.maps_url` goes away; links are derived from `lat`/`lng`.
- **No third-party tiles at view time.** Not `tile.openstreetmap.org`: every page view would
  send the visitor IP to OSMF (privacy notice / two-click consent, CSP widened), and the OSMF
  tile policy explicitly discourages caching proxies and forbids pre-seeding / tile archives.
- **Self-hosted vector map:** a regional PMTiles extract of the Protomaps daily build (OSM data,
  ODbL) rendered with MapLibre GL. Everything is served from our own origin → CSP unchanged
  (`connect-src 'self'`, `worker-src 'self' blob:`, `img-src 'self' data: blob:` already fit).
- **Tile file follows the BLZ pattern, but is fetched automatically** (see phase 3):
  resolution order `MAP_TILES_FILE` env → `/data/map/region.pmtiles` (uploads volume) → none.
  Nothing is committed to git and nothing is baked into the image.
- **Graceful degradation, like `Bbh.Blz`:** no tile file, no JS, or location outside the
  extract's bbox → address + OSM links only, no embedded map. Never an error.

Verification after every phase: `mix compile --warnings-as-errors && mix format && mix test`.

---

## Phase 1 — Google out (small, standalone PR)

1. `BbhWeb.EventHTML`: add `osm_url/1` and `osm_route_url/1` (take a `%Location{}`, return
   `nil` when `lat` or `lng` is `nil`).
   - view:  `https://www.openstreetmap.org/?mlat={lat}&mlon={lng}#map=17/{lat}/{lng}`
   - route: `https://www.openstreetmap.org/directions?to={lat},{lng}`
   - Format floats with a fixed precision (6 decimals) — no scientific notation.
2. `event_html/show.html.heex`: replace the `maps_url` link with „Auf OpenStreetMap ansehen“
   and „Route planen“ (`target="_blank" rel="noopener"`).
3. Remove `maps_url`:
   - `Bbh.Calendar.Location` schema + `cast` list
   - `admin/location_live/form.ex` (input „Karten-URL“)
   - `mix/tasks/bbh.import.ex` (`"maps_url" => y["maps"]`)
   - migration `remove :maps_url, :string` (reversible)
   - grep tests/fixtures/seeds (`calendar_fixtures.ex`, `schuetzenfest_demo.exs`, `location_live_test.exs`)
4. `event_jsonld`: extend the `Place` with `"geo" => %{"@type" => "GeoCoordinates", ...}` and a
   `PostalAddress` when street/zip/city are present.
5. Data check (prod, read-only): list locations with `lat IS NULL OR lng IS NULL` and sanity-check
   that coordinates are in the region (the Hugo source swapped lat/lng — the import corrects it,
   verify a couple on the map).
6. Tests: helper unit tests (nil, normal, precision); controller test that the event page
   contains the OSM link and no `google`.

## Phase 2 — Embedded map

### 2a. Serving the PMTiles file
- PMTiles is read by the browser with HTTP **Range** requests. Traefik passes straight to
  Phoenix. **Verify first** whether `Plug.Static` in our Plug version answers `Range` with 206;
  assumption: it does not → small controller.
- `BbhWeb.MapTilesController`, route `GET /karte/region.pmtiles` (public pipeline, no session):
  - resolve the file via `Bbh.Map.tiles_path/0` (nil → 404)
  - parse a single `Range: bytes=a-b` / `bytes=a-` (multi-range → 416 or full 200), clamp to size
  - `send_file(conn, 206, path, offset, length)` with `Content-Range`, `Accept-Ranges: bytes`
  - `ETag` = file mtime+size, `Cache-Control: public, max-age=86400`; `If-None-Match` → 304
  - no Range header → 200 full file (fine for curl/debugging)
- Tests: 206 with correct bytes, open-ended range, out-of-bounds → 416, missing file → 404.

### 2b. Frontend
- Vendor (no npm, like Quill/Flatpickr) into `assets/vendor/maplibre/` and `assets/vendor/pmtiles/`:
  MapLibre GL JS (+ CSS), `pmtiles` JS, Protomaps basemap style module (`@protomaps/basemaps`).
  Pin versions in a `VERSIONS` note; the basemap style major must match the tile schema of the
  build we fetch (check `pmtiles show` metadata).
- Self-host glyphs + sprites from `protomaps/basemaps-assets` under `priv/static/map/` — only the
  font stacks/sprite flavours actually used (light + dark), otherwise the style pulls them from
  GitHub/CDN and the CSP blocks it.
- **Separate bundle:** second esbuild profile `bbh_map` → `priv/static/assets/js/map.js` (+ css).
  Add it to `assets.build` / `assets.deploy` / watchers in dev. Loaded only on event pages with a
  map, via `<script defer nonce={@csp_nonce} src=...>` (`'strict-dynamic'` allows it).
- `map.js`: registers `pmtiles://` protocol, finds `[data-location-map]` elements, reads
  `data-lat`, `data-lng`, `data-name`, `data-tiles-url`, theme from `<html data-theme>`, builds the
  map: one marker, `cooperativeGestures: true` (no scroll hijack), zoom ~16, min/max zoom bounded
  to the extract, attribution control always visible. React to theme toggle (swap style flavour).

### 2c. Component
- `<.location_map location={...} />` in `site_components.ex`:
  - renders only if `Bbh.Map.available?()` and the location is inside `Bbh.Map.bbox()`
  - `aspect-video rounded-lg border`, `role="img"` + `aria-label="Karte: {name}"`
  - a visible attribution fallback in markup: „Kartendaten © OpenStreetMap-Mitwirkende“ (ODbL),
    plus Protomaps credit
- Use it in `event_html/show.html.heex` inside the location box, links from phase 1 below it.
- Test: component renders with file + in-bbox; renders nothing without file / outside bbox.

### 2d. ADR 0014
Context (Google, OSMF tile policy, privacy, CSP), decision (self-hosted PMTiles + MapLibre,
Range controller, separate bundle, auto-fetch), consequences (bundle size only on event pages,
dependency on Protomaps build server only for refreshes, not for page views).

## Phase 3 — Automatic fetch & refresh of the tile file

Answer to „like BLZ?“: same resolution order and graceful degradation as `Bbh.Blz`, but unlike
the BLZ file it is **not committed** and **not refreshed by hand** — the app fetches it itself.
Reason: the bbox should follow the locations in the DB, which only the running app knows, and a
multi-MB binary would bloat git history on every refresh.

### 3a. `pmtiles` CLI in the image
- `Dockerfile` final stage: download the pinned `go-pmtiles` release binary (single static
  binary) for the target arch, **verify SHA256**, install to `/usr/local/bin/pmtiles`.
- `renovate.json`: regex manager for the pinned version (+ checksum update is manual or via
  `# renovate:` comment convention — decide when implementing).
- Dev: README note to install the CLI locally; without it the task logs a warning and does nothing.

### 3b. `Bbh.Map` (context)
- `tiles_path/0` (resolution order above), `available?/0`, `bbox/0` (read from the PMTiles
  header once, cached in `:persistent_term`, invalidated on swap), `needed_bbox/0` (all located
  `locations` + ~3 km margin, union with a fixed default „Gronau/Epe“ box so the extract never
  collapses to a single point).

### 3c. `Bbh.Workers.MapTilesUpdater` (Oban, queue `default`, `unique: [period: 3600]`)
1. Find the newest build: try `https://build.protomaps.com/YYYYMMDD.pmtiles` for today−1 back to
   today−10 with a `HEAD` via `Req` (daily builds are only retained for a limited time — verify
   retention); first 200 wins.
2. `pmtiles extract <build-url> /data/map/region.pmtiles.tmp --bbox=<needed_bbox> --maxzoom=15`
   via `System.cmd/3` with a timeout; stream log output to `Logger`.
3. Validate: exit status 0, file > some minimum size, `pmtiles show` parses, tile schema major
   matches the vendored basemap style. On any failure: delete `.tmp`, keep the old file, log
   warning, return `{:error, ...}` (Oban retries with backoff, max 3).
4. Atomic `File.rename/2` → `region.pmtiles`, invalidate the bbox cache.
- Triggers:
  - **Cron** in `config :bbh, Oban` — monthly, e.g. `{"17 4 3 * *", Bbh.Workers.MapTilesUpdater}`.
  - **Boot:** after startup, enqueue once if no file exists (so a fresh Beta/dev self-heals).
  - **Location saved** with coordinates outside the current bbox → enqueue (unique dedupes).
  - **Manual:** `mix bbh.map.update` (dev) / release eval command for the server.
- Config: `config :bbh, Bbh.Map, enabled: true, maxzoom: 15, build_base_url: ...`;
  `enabled: false` in `test.exs` — no network, no CLI in tests. Worker tests stub the command
  runner and HTTP (Req.Test).

### 3d. Ops
- Directory `/data/map/` lives in the existing `uploads` volume → survives deploys, is in the
  backup unless excluded — **exclude it in `backup.sh`** (regenerable, no need to back it up).
- Beta fetches its own copy via the same boot/cron trigger; nothing to add to `sync-data.sh`.
- Check that the app container has outbound HTTPS (it does for push; the 2 GiB resource ceiling
  is plenty for `pmtiles extract`, which is I/O-bound).

## Open questions
- Locations outside the region (Ausflüge etc.): only links, or grow the bbox? (Plan: grow the bbox
  automatically via `needed_bbox/0`, but cap it — e.g. ignore locations >50 km away and show
  links only for those, so one far-away trip doesn't pull a huge extract.)
- `maxzoom` 15 vs 16: check extract size for the Gronau/Epe box first, then decide.
- Admin form map picker (click to set `lat`/`lng`) — follow-up, reuses `map.js`.

## Deferred / Skipped
- Clustered overview map on `/termine` — not needed now.
- Routing inside our own map — out of scope; route link goes to openstreetmap.org.

## Implementation notes (2026-10-24)
- **Range serving:** Plug 1.20's `Plug.Static` already answers `Range` (206/416/ETag/304),
  so instead of `MapTilesController` there is `BbhWeb.Plugs.Map` in the endpoint, which
  points `Plug.Static` at the runtime-resolved archive. Same plug serves glyphs/sprites
  from `priv/map` under `/karte`, answering unshipped glyph ranges with an empty set.
- **Reverse proxy:** prod is behind Traefik (compress middleware), dev behind Caddy;
  tiles are sent with `Cache-Control: no-transform`, verified uncompressed 206 via Caddy.
  Re-check on Beta: `curl -sI -H 'Range: bytes=0-126' -H 'Accept-Encoding: gzip' …/karte/region.pmtiles`.
- **maxzoom:** Protomaps builds stop at z15 → 15 is fixed (MapLibre overzooms to 18).
  Home extract with current venues: ~9–11 MB.
- **Far locations:** capped at 50 km from the home box; beyond that links only.
- **Vendoring:** single dir `assets/vendor/map/` (MapLibre 6.15.0 ESM + worker,
  pmtiles 4.5.0 + fflate 0.8.3, @protomaps/basemaps 5.7.2), `VERSIONS.md` there.
  MapLibre 6 is ESM-only with a module worker → `bbh_map` profile builds `--format=esm`
  with the worker as second entry point; `map.js` is a nonced `type="module"` script.
- **Glyphs:** only Latin/Greek/Cyrillic/punctuation ranges (~2.3 MB) committed.
- **Attribution:** a visible `<figcaption>` (OSM/ODbL + Protomaps) instead of the
  MapLibre control; the figure is `hidden` until the script mounts the map.
- **Validation** reads the PMTiles header + metadata in Elixir (`Bbh.Map.read_header/1`)
  rather than parsing `pmtiles show` output.
- **pmtiles CLI** in both Dockerfiles (dev image too, so dev self-heals on boot).
  Renovate rule: `extractVersion ^v`, never automerge (checksums are manual).
- **Manual run on the server:** `bin/bbh rpc "Bbh.Map.enqueue_update()"`.
