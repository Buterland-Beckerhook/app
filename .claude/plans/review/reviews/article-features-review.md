# Review — article features (commit `7b25088`)

**Scope:** the article-features delta only (logo fallback, exclusive preview image,
gallery lightbox). Prior remediation commits were reviewed earlier this session.
**Agents:** elixir-reviewer · security-analyzer · testing-reviewer · requirements-verifier

## Verdict: PASS WITH WARNINGS

Feature is correct, secure, and meets all three requirements. The one thing worth
fixing is **two ineffective (tautological) tests** that give false confidence in the
logo fallback. No runtime blockers.

## Requirements Coverage — 3 MET
1. Logo fallback (listing + article page) — **MET** (`hero_image/1`, both call sites; real image still wins via `article_hero/1`).
2. Exclusive switchable preview — **MET** (`set_article_preview_image/2` transaction clears siblings; public hero consumes the flag).
3. Gallery lightbox — **MET** (triggers rendered; JS opens native `<dialog>`; browser interaction is intentionally not unit-tested).

## Security — CLEAN (no findings)
- IDOR on `set_article_preview_image/2`: UPDATE is double-scoped by `article_id` from `socket.assigns` → cross-article flip impossible.
- Lightbox XSS: `image_alt`/`media_url` are HEEx-escaped and land only on `img.alt`/`img.src` (no HTML sink; `javascript:` doesn't execute on `<img src>`).
- CSP: runtime `<style>` allowed by `style-src 'self' 'unsafe-inline'`; no inline script.

## Findings

### WARNING (test quality)
- **W1 [CONFIRMED] `article_controller_test.exs:37,55`** — `assert html =~ "/images/logo.svg"` is tautological: the logo URL is on every page (og:image `root.html.heex:19`, nav logo `layouts.ex:73`). These tests pass whether or not the fallback fires. **Fix:** assert the fallback-specific marker (the hero `alt="Buterland-Beckerhook"` + `object-contain`), and add a positive-path test that a real hero renders `/media/...` and NOT the fallback.

### WARNING (correctness, minor)
- **W2 [CONFIRMED] `content.ex:139-150`** — `set_article_preview_image/2` uses raw `update_all`, so `ArticleImage.updated_at` is never bumped. No functional impact (ordering is by `sort`), but timestamps go stale. **Fix:** add `updated_at: {:placeholder, :now}` (or `DateTime.utc_now/1`) to both `set:` lists.

### SUGGESTION
- **S1 `content.ex:141-146`** — no-partial-clear-on-not-found relies on `Repo.transact` auto-rollback; add a one-line comment so a future `Repo.transaction` refactor doesn't silently break it.
- **S2 `article_live_test.exs:59`** — `set_preview_image` is driven via `render_click(event)` not the real button; consider `element(lv, "button[phx-value-img_id=…]") |> render_click()` and assert the re-rendered ★ state.
- **S3 `show.html.heex:24-25`** — `hero` var (needed for gallery exclusion) duplicates the `article_hero/1` call `<.hero_image>` makes internally; harmless.

### PRE-EXISTING (noted, not in this diff)
- `format.ex:60-64` — `article_hero/1` returns `nil` on `%Ecto.Association.NotLoaded{}`, which would silently show the logo instead of erroring if a future call site forgets to preload.
- `form.ex:82-84` — `set_preview_image` error branch doesn't `reload_images/1` (stale-UI edge case).
- `attr :map` (not typed structs) on site components — existing pattern.

## Recommended next step
Fix W1 (real value — the tests currently don't verify the feature) and W2 (cheap).
S1–S3 optional. Then re-run `mix test`.
