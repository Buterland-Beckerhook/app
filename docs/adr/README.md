# Architecture Decision Records

Short records of non-obvious architectural decisions — the **why**, not the
what (the code shows the what). One file per decision, numbered.

- [0001](0001-rate-limiting-with-hammer.md) — Rate limiting with Hammer (ETS backend)
- [0002](0002-sanitize-trix-html-on-write.md) — Sanitize Trix rich-text HTML on write
- [0003](0003-altcha-replay-cache.md) — Altcha proof-of-work hardening (signed expiry + ETS replay cache)
- [0004](0004-media-library-owns-image-metadata.md) — The media library owns image metadata; rotation rewrites the original
- [0005](0005-email-obfuscation.md) — E-mail obfuscation with CSS decoys, not JavaScript assembly
- [0006](0006-media-folder-tree-and-drag-and-drop.md) — The media library shows its whole folder tree, and moves happen by dragging
- [0007](0007-media-tree-edit-mode-and-collapsing.md) — Sorting the media folder tree is a mode; outside it branches fold and a folder shows its whole branch
- [0008](0008-gallery-slideshow.md) — The Diashow crops to one shared frame, and the strip that scrolls it is CSS
