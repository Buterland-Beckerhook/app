# ADR 0002 — Sanitize Trix rich-text HTML on write

**Status:** Accepted (2026-07-14)

## Context

Admin rich-text fields use the Trix editor and store raw HTML in `body`
columns (articles, events, and the `richtext`/`alert`/`media_card` page
blocks). Those bodies are rendered on public pages with `raw/1`. Editors
are trusted staff, but a stored `<script>` or `onerror=` handler — whether
pasted by accident or via a compromised editor account — would be
**persisted** and re-served to every public visitor (stored XSS).

## Decision

Add `{:html_sanitize_ex, "~> 1.4"}`. Introduce `Bbh.Html.sanitize/1`, a
thin wrapper over `HtmlSanitizeEx.basic_html/1`, and apply it via
`update_change(:body, &Bbh.Html.sanitize/1)` in every changeset that
accepts Trix HTML.

Sanitize **on write** (store already-clean HTML), not on render.

## Consequences

- Rationale for on-write: the render path stays a cheap `raw/1`; data at
  rest is clean; and there is a single choke point (the changesets) rather
  than one per template. All existing `raw/1` render sites are now safe by
  construction.
- `basic_html` preserves the formatting Trix actually emits (headings,
  lists, links, bold/italic) while dropping `<script>` and `on*` handlers.
  If a future block needs richer markup, pick a wider scrubber
  deliberately rather than bypassing sanitization.
- Media-library inserts (added 2026-07-15) rely on `basic_html` already
  allowing `<img>`/`<a>` whose URL is scheme-less or `http`/`https`/`mailto`.
  Our media picker emits scheme-less `/media/...` URLs, so images and
  download links survive sanitization while `javascript:`/`data:` URLs and
  inline handlers (e.g. `onerror`) are still stripped — verified by tests.
  No custom scrubber was needed; the picker never inserts anything
  `basic_html` would reject.
- A deploy that already had dirty rows would need a one-time backfill.
  Moot here: the database is fresh and nothing is deployed yet.
