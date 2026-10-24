# ADR 0013 — Rich-text images are stored bare and enriched at render time

**Status:** Accepted (2026-10-24)

## Context

Editors insert pictures into running text through the media picker, which puts an
inline `<img src="/media/<key>" alt="…">` into the current paragraph. That image was
served as the full-size original — no `srcset`, no dimensions (so the page shifted as
it loaded), no lightbox and no caption. Editors also wanted text to wrap around a
picture, which Quill can only express as a class on the `<img>`.

The obvious target markup is a `<figure>` with a `<figcaption>`. Storing it would
break things that are cheap to keep:

- `Bbh.Html.sanitize/1` merges Quill's one-`<p>`-per-line output by tokenizing the
  top-level blocks (`p`, `h1–6`, `ul`, `ol`, `blockquote`, `pre`). Any other top-level
  element makes the tokenizer give up and skip the merge for the whole body.
- Quill has no figure blot; the editor would need a custom one that round-trips
  caption markup it must never let the author edit.
- The caption belongs to the media library (ADR 0004). A stored copy drifts the moment
  someone fixes a typo in the library — exactly the problem ADR 0004 removed.
- Every image already in the database would need a migration to benefit.

## Decision

**Store the bare inline `<img>` plus whitelisted classes** (`bbh-img-*` for size,
`bbh-float-left|right` for wrap, `bbh-cap-none|caption|copyright` for what the line
under the image shows; no class means caption and copyright) — nothing else. **Enrich at render time** in
`BbhWeb.RichtextImages.rewrite/1`, a step of `BbhWeb.Format.render_richtext/1`:

- All `/media/<key>` images of a body are resolved with one query
  (`Bbh.Media.get_uploads_by_storage_keys/1`); a body without one costs none.
- Each becomes a `<span class="bbh-fig …">` wrapper — spans, because the image sits
  inside a `<p>` and a block element would make the parser close the paragraph — with a
  lightbox `<button>`, an `<img>` with `srcset`/`sizes` capped at the original width
  and `width`/`height`, and a caption line (Bildunterschrift + ©) read live from the
  media library. The stored classes move to the wrapper, which the CSS sizes and floats.
- Alt text comes from the library too. The `alt` the picker wrote is only the snapshot
  taken at insert time.
- Rich-text, gallery and article hero images share the lightbox group `content`, so one
  lightbox walks a page's pictures in document order. The lightbox always shows caption
  and copyright, whatever the `bbh-cap-*` choice for the page.
- The step runs before `EmailObfuscation.rewrite/1`, so obfuscation stays last and also
  covers an address in a caption.

Anything that is not a known media image (external URL, unknown key, PDF) is left
untouched. An image the author linked keeps its link and gets no lightbox button.

## Consequences

- No migration; all existing content got responsive images, dimensions, a lightbox
  and captions on deploy.
- A caption or alt fix in the media library shows up everywhere immediately.
- The editor shows a bare `<img>`, the page a wrapper, so the CSS for size and float is
  written twice (`.ql-editor img.bbh-*` and `.prose .bbh-fig.bbh-*`).
- Below the md breakpoint nothing floats and every image is full width. Size classes
  only apply from 48rem up.
- Every new upload carries the club as its default copyright, so without a choice every
  image would show "© Buterland-Beckerhook e.V."; the `bbh-cap-*` picker is how an
  editor drops it (or the caption) for a single image.
- Render cost: one indexed query per rich-text block that contains a media image.
