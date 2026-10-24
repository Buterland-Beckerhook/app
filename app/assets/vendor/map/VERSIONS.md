# Vendored map libraries

Self-hosted map stack for the event location map (`assets/js/map.js`, ADR 0014).
No npm: the files are copied from the published npm tarballs (integrity checked
against the registry's `sha512`), with the trailing `//# sourceMappingURL=` line
removed. Built into its own bundle by the `bbh_map` esbuild profile.

| File | Package | Version | License | Source path in the tarball |
| --- | --- | --- | --- | --- |
| `maplibre-gl.mjs`, `maplibre-gl-worker.mjs`, `maplibre-gl.css` | `maplibre-gl` | 6.15.0 | BSD-3-Clause (`LICENSE-maplibre-gl.txt`) | `dist/` |
| `pmtiles.mjs` | `pmtiles` | 4.5.0 | BSD-3-Clause | `dist/esm/index.js` |
| `fflate.mjs` | `fflate` (dependency of `pmtiles`) | 0.8.3 | MIT | `esm/browser.js` |
| `basemaps.mjs` | `@protomaps/basemaps` | 5.7.2 | BSD-3-Clause | `dist/esm/index.js` |

`pmtiles.mjs` imports the bare specifier `fflate`; the esbuild profile aliases it to
`fflate.mjs`.

Glyphs and sprites live in `priv/map/` (served at `/karte/fonts`, `/karte/sprites`),
from `protomaps/basemaps-assets` at commit `028c18f713baecad011301ff7a69acc39bcc2ae7`:
the three Noto Sans stacks the style uses (OFL, `priv/map/fonts/OFL.txt`), Latin,
Greek, Cyrillic and punctuation ranges only, and the `v4` light/dark sprites. A
glyph range we don't ship is answered with an empty glyph set, so such characters
are just left out of a label.

## Compatibility

The style module's major must match the tile schema of the Protomaps build the
updater fetches: `@protomaps/basemaps` 5.x renders schema 4.x (`version` in the
archive metadata — `pmtiles show region.pmtiles`). `Bbh.Map.tile_schema_major/0`
holds the expected major; the updater refuses an archive with any other.

## Updating

1. Download the new tarballs (`npm pack <pkg>@<version>`), compare their sha512
   with `npm view <pkg>@<version> dist.integrity`.
2. Copy the files above, drop the `sourceMappingURL` line, update this table.
3. On a basemaps major bump, check the schema it expects and update
   `tile_schema_major/0` together with the sprite flavour directory (`v4`).
