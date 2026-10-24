# ADR 0014 — The event map is a self-hosted PMTiles extract, fetched by the app itself

**Status:** Accepted (2026-10-24)

## Context

An event page showed its venue as a „Karte anzeigen" link to Google Maps, stored per
location (`locations.maps_url`). We wanted to stop sending visitors to Google and to
show the venue on an embedded map.

The obvious embed, `tile.openstreetmap.org` raster tiles in Leaflet, fails on two
counts:

- **Privacy.** Every page view would send the visitor's IP address to the OSMF tile
  servers. That needs a line in the privacy notice and, by the stricter reading,
  two-click consent, and the CSP would have to admit a third-party origin for
  images.
- **Tile usage policy.** The OSMF policy discourages caching proxies in front of its
  servers and forbids pre-seeding or bulk tile archives, so we couldn't simply serve
  its tiles from our own origin either.

The area that matters is tiny: the venues are in Gronau and Epe, with the odd one in
a neighbouring town.

## Decision

**Links are derived, not stored.** `maps_url` is dropped. „Auf OpenStreetMap
ansehen" and „Route planen" are built from `lat`/`lng` (`BbhWeb.EventHTML.osm_url/1`,
`osm_route_url/1`), and the Event JSON-LD gets `geo` and a `PostalAddress`.

**The map is a regional vector extract, served from our own origin.** Protomaps
publishes a daily planet build of OSM data (ODbL) as one PMTiles archive. The `pmtiles`
CLI cuts a bounding box out of it using HTTP range requests, so only that region is
downloaded (~10 MB at zoom 0–15; the builds stop at 15 and MapLibre overzooms past it).
MapLibre GL renders it with the Protomaps basemap style, light or dark following the
site theme. Tiles, glyphs, sprites and the MapLibre worker all come from our own
origin, so the CSP stays unchanged (`connect-src 'self'`, `worker-src 'self' blob:`).

- **Serving:** `BbhWeb.Plugs.Map` sits in the endpoint ahead of session and router.
  `/karte/region.pmtiles` hands the runtime-resolved file to `Plug.Static`, which
  already answers single `Range` requests (206, 416, ETag/304); no hand-written range
  parsing. The tiles URL carries the archive's version (mtime + size), so a day of
  `max-age` is safe, and `no-transform` keeps a compressing proxy off the byte
  ranges. Glyphs (Latin, Greek, Cyrillic and punctuation ranges of the three Noto
  stacks, ~2.3 MB) and sprites are committed under `priv/map`. A glyph range we
  don't ship is answered with an empty glyph set instead of a 404, so a stray
  character can't fill the 404 log (ADR 0011); the label just leaves it out.
- **Frontend:** MapLibre, `pmtiles` and the style module are vendored (no npm, like
  Quill) and built by a second esbuild profile into `assets/map/` — about 1.6 MB,
  loaded only by pages that show a map, as a nonced module script. The figure starts
  `hidden` and the script reveals it once a map is mounted, so without JavaScript or
  WebGL the page shows address and links and no empty box. Cooperative gestures keep
  the map from hijacking page scroll. The attribution is a visible caption in the
  markup, not a collapsible control.
- **Fetching:** the archive is not committed and not baked into the image. The app
  fetches it itself (`Bbh.Workers.MapTilesUpdater`): it finds the newest daily build
  (they are kept for about a week), extracts `Bbh.Map.needed_bbox/0`, checks the
  result (size, PMTiles header, tile schema major matching the vendored style) and
  swaps it in with an atomic rename. On any failure the old archive stays. Triggers:
  monthly cron, boot when no archive exists, saving a location outside the covered
  area, and `mix bbh.map.update` / `bin/bbh rpc "Bbh.Map.enqueue_update()"`.
- **The area follows the data.** `needed_bbox/0` is a fixed Gronau/Epe box, plus every
  located venue within 50 km with 3 km of room around it. A venue farther away (a
  club trip) doesn't grow the extract; its page keeps the links only.
- **Degrades like `Bbh.Blz`.** Resolution order is `MAP_TILES_FILE` (which also pins
  the archive against updates), then `<dir>/region.pmtiles` (`/data/map` in the
  uploads volume). No archive, or a location outside it, means no embedded map and
  never an error.

## Consequences

- No third-party request on a page view, so no consent banner and no CSP change. The
  Protomaps build server is contacted only by the updater, about once a month.
- The image ships one more static binary (`pmtiles`, pinned and checksum-verified in
  both Dockerfiles). Renovate bumps its version but cannot update the checksums, so
  those PRs never auto-merge.
- The archive lives in the uploads volume but `backup.sh` doesn't include it (it only
  archives `/data/uploads`); it is regenerable. `sync-data.sh` copies it to Beta
  along with the rest of the volume, and Beta also refreshes it on its own schedule.
- A Protomaps tile schema major bump needs a matching `@protomaps/basemaps` major
  (and sprite set). Until then the updater refuses the new builds and the old archive
  keeps serving, so the map ages rather than breaks.
- The extract is cut at a fixed size; venues added later outside it trigger a new
  extract the moment they are saved.
