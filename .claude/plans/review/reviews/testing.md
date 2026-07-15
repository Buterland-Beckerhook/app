# Test Review: Article features (commit 7b25088, feat/phoenix-rewrite)

## Summary
Focused review of the three changed test files for the article-preview-image /
logo-fallback / lightbox-gallery features. `content_test.exs` exclusivity tests are solid.
The two `=~ "/images/logo.svg"` assertions in `article_controller_test.exs` are
**tautological / not meaningful** — confirmed by reading the templates: the string is
present on every page regardless of which code path renders. The lightbox-gallery test is
meaningful. The admin LiveView `set_preview_image` test is a valid check of the handler but
bypasses the real click path and misses a UI-state assertion.

## Iron Law Violations
None in these three files (`async: true` present throughout, no `Process.sleep`, no mocking,
`DataCase`/`ConnCase` used correctly, sandbox isolation intact).

## Issues Found

### Critical
- [ ] **CONFIRMED — tautological assertion.**
  `test/bbh_web/controllers/article_controller_test.exs:34-38` (show, no images) and
  `:52-56` (listing card, no images) assert `html =~ "/images/logo.svg"`. But
  `app/lib/bbh_web/components/layouts/root.html.heex:19` unconditionally renders
  `<meta property="og:image" content={~p"/images/logo.svg"} />` on **every** page, and
  `app/lib/bbh_web/components/layouts.ex:73` renders the header/nav logo on every page too.
  Both tests would pass identically even if `hero_image/1`
  (`app/lib/bbh_web/components/site_components.ex:19-38`) rendered a real photo instead of
  the fallback `<img src={~p"/images/logo.svg"} alt="Buterland-Beckerhook" .../>` — the
  substring is guaranteed present regardless of the code path under test, so these two tests
  currently assert nothing about the fallback logic they claim to cover.
  Fix: scope the assertion to the fallback-specific markup, e.g.
  `html =~ ~s(alt="Buterland-Beckerhook")` (the fallback's unique `alt`), or parse with Floki
  and assert on the hero container specifically.

### Warnings
- [ ] **PLAUSIBLE — admin preview-image test bypasses the real UI click path.**
  `test/bbh_web/live/admin/article_live_test.exs:52-64` calls
  `render_click(lv, "set_preview_image", %{"img_id" => b.id})` directly, rather than clicking
  the rendered button (`app/lib/bbh_web/live/admin/article_live/form.ex:237-248`:
  `phx-click="set_preview_image" phx-value-img_id={img.id}`). This verifies the
  `handle_event`/context logic and DB state but never proves the template actually renders a
  clickable control wired with the expected param key/value for each image. Prefer
  `lv |> element("button[phx-value-img_id='#{b.id}']") |> render_click()`.
  Also missing: an assertion on the *re-rendered html* reflecting the new UI state (★ badge
  moves to `b`, button for `a` becomes enabled/`btn-outline` again) — only flash text and Repo
  state are checked today, not what the admin user would actually see change on screen.
- [ ] **Coverage gap — no positive-path assertion that a real hero image suppresses the logo
  fallback.** Nothing in `article_controller_test.exs` asserts that when an article *has* an
  image, `alt="Buterland-Beckerhook"` (or the fallback's `object-contain` class) is **absent**
  and the real `media_url`-derived `src` is present instead. Without this, the two logo
  fallback tests provide effectively zero coverage of the `hero_image/1` conditional
  (`app/lib/bbh_web/components/site_components.ex:19-38`).
- [ ] **Coverage gap — no end-to-end test that switching the admin preview image changes the
  public-facing hero/gallery.** `set_article_preview_image/2`
  (`app/lib/bbh/content.ex:139-148`) and the public hero-selection logic
  (`app/lib/bbh_web/format.ex:60-64`: `Enum.find(images, & &1.use_as_article_image) ||
  List.first(images)`) are each tested in isolation but never chained — e.g. mark image B as
  preview, then GET `/aktuell/:year/:slug` and assert B's URL is the rendered hero `src` and B
  is excluded from the gallery while A now appears in it.

### Suggestions
- [ ] `content_test.exs:122-135` (exclusivity, both directions) and `:137-141` (foreign image
  id → `{:error, :not_found}` via `Ecto.UUID.generate()`) are strong, pattern-matching,
  deterministic assertions with no flakiness risk — no changes needed.
- [ ] Gallery/lightbox test (`article_controller_test.exs:40-48`) is **confirmed meaningful,
  not tautological**: the fixture adds two images via `add_article_image/2`,
  `article_hero/1` selects exactly one as hero (first image, absent an explicit
  `use_as_article_image` flag), guaranteeing the `Enum.reject/2` gallery in
  `show.html.heex:38` retains exactly one non-hero image, so the `data-lightbox-src` button
  (`show.html.heex:42-49`) is genuinely exercised. No change needed here.
