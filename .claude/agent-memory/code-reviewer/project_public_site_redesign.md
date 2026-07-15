---
name: public-site-redesign
description: feat/phoenix-rewrite carries a design-handoff restyle of the public site; scope decisions that look like inconsistencies are intentional
metadata:
  type: project
---

The public Schützenverein site was restyled per a design handoff (2026-07): self-hosted webfonts (GDPR — no font CDN), new green daisyUI token palette, sticky header, dark-green footer.

**Why:** design handoff for the German club homepage; GDPR forbids Google-Fonts-style CDNs.

**How to apply when reviewing this repo:**
- The gray/zinc → token sweep deliberately covers only public templates; `admin/` LiveViews and `core_components.ex` were intentionally left on stock classes — do not flag that as an incomplete sweep.
- Token semantics: daisyUI `primary` = accent text/link green, `accent` = CTA button background (they diverge only in dark mode). `--bb-*` custom vars feed `text-muted` / `bg-tag` / `bg-card` via `@theme inline`.
- The footer is hard-coded `#0d2617` in both themes on purpose (handoff), and `theme_toggle` is styled specifically for that dark footer.
