# Vendored JavaScript

No npm: these files are copied from the published packages. Renovate reads the
version column (and the one in `map/VERSIONS.md`) and opens a PR when a package has a
newer release. That PR only changes this table; replace the files by hand in the same
PR. The map stack is documented in `map/VERSIONS.md`.

| File | Package | Version | License | Source |
| --- | --- | --- | --- | --- |
| `altcha/altcha.js`, `altcha/i18n/de.js` | `altcha` | 3.6.0 | MIT | `dist/main/altcha.js`, `dist/i18n/de.js` (server contract: `lib/bbh/altcha.ex`) |
| `quill/quill.js`, `quill/quill.snow.css` | `quill` | 2.0.3 | BSD-3-Clause | `dist/` |
| `flatpickr/flatpickr.min.js`, `flatpickr/flatpickr.min.css`, `flatpickr/l10n/` | `flatpickr` | 4.6.13 | MIT | `dist/` |

## Known advisories

- **quill 2.0.3: CVE-2025-15056 / GHSA-v3m3-f69x-jf25.** This is an XSS in the HTML export (`getSemanticHTML()`) via the video, formula and code-block blots. No fixed release exists yet.
  - Mitigations: the editor is admin-only, and `assets/js/lazy/editor.js` restricts Quill to an explicit `formats` list without those blots. The server scrubs the stored HTML in any case (`Bbh.Html.RichScrubber`).
  - Drop this note once a patched release replaces 2.0.3.
