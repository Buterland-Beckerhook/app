# ADR 0011 — Redirects are resolved on the 404 path only

**Status:** Accepted (2026-10-23)

## Context

The relaunch replaces the Hugo site at the same domain. Most old URLs survive unchanged —
the import derived slugs the way Hugo built paths, and `BbhWeb.Plugs.TrailingSlash`
absorbs Hugo's trailing slashes — but not all of them:

- Hugo kept `_` and `ß` from file names (`/aktuell/2020/kein_biwak/`,
  `/aktuell/2019/pokal-und-preisschießen/`); `Bbh.Slug.slugify/1` turns them into `-` and
  `ss`. 13 articles and 26 events in the Hugo repo are affected.
- Front-matter `aliases:` were imported into `articles.aliases` but never served.
- Hugo generated URLs the new site has no equivalent for: per-event `index.ics`, year
  sections, `/aktuell/page/N/`, `/tags/…`, `/index.xml`, `/datenschutzerklaerung/`.
- The `/verein/…` pages were rebuilt by hand under new paths; no rule can map them.

Old links live on in Facebook posts, PDFs, Google's index and calendar subscriptions. And
after go-live new cases will keep turning up that nobody can predict today.

## Decision

**A single 404 path.** Both kinds of "not found" end in `BbhWeb.Redirector.not_found/1`:
a GET that no route claims (a final catch-all `get "/*path"`, `BbhWeb.NotFoundController`)
and a controller that finds no record (`BbhWeb.ControllerHelpers.not_found/1` delegates).
Only there are redirects consulted. Consequences:

- **A redirect can never shadow a live page.** If the content exists, it is served.
- **Normal requests pay nothing.** No lookup, no plug in the hot path.
- One place to change 404 behaviour (and, later, the 404 page itself).

**Two sources, rules first** (`Bbh.Redirects.resolve/1`):

1. *Rules* — rows in `redirects`, managed at `/admin/weiterleitungen` (admin-only: a rule
   can send any URL anywhere). Exact before prefix (`/…/*`), longest prefix first. Kept in
   a `:persistent_term` map that every write through `Bbh.Redirects` erases; the next
   lookup rebuilds it. The cache is off in test (node-global vs. per-test sandboxes).
2. *Legacy* — `Bbh.Redirects.Legacy` maps Hugo URLs **by rule, not by table**: slugify
   the old name and look the content up; check `articles.aliases`; translate the
   generated section/feed URLs. Only targets that resolve are returned. Because it follows
   the content, a renamed or deleted article needs no maintenance here; because rules
   win, any legacy answer can be overridden in the admin.

Paths are compared normalized (percent-decoded, lowercase, no trailing slash, no query),
so `/Aktuell/2019/Pokal-und-Preisschie%C3%9Fen/` and `…/pokal-und-preisschießen` are one
key. Legacy and permanent rules answer `301`, temporary rules `302`.

**A 404 log.** Misses that survive both sources are aggregated per normalized path in
`not_found_paths` (hits, last seen, external referrer as host + path). The admin lists
them by frequency with one-click „Weiterleitung anlegen“ (prefills the source) and
„Ignorieren“. Creating a rule deletes the log entries it covers. Guard rails, because
this is the one table an anonymous client can write to:

- not logged: `/admin`, `/users`, `/api`, `/media`, `/oauth`, `/mcp`, `/kalender/geteilt`
  (paths carry revoked share tokens) and obvious scanner probes (`.php`, `/.env`, `wp-`,
  key files, source maps…), decided on the normalized path (`Bbh.Redirects.ignored_not_found?/1`);
- a hard ceiling of 5 000 rows — past it, known paths keep counting but new ones are not
  added;
- the write runs off-request in `Bbh.TaskSupervisor`;
- `Bbh.Workers.NotFoundPruner` drops entries not hit for 90 days, and any entry the
  ignore list has since come to match.

## Alternatives rejected

- **A redirect plug in front of the router.** Would have to look up every request, and a
  rule could hide a real page — the failure nobody notices.
- **Seeding a redirect table from the import.** A snapshot of today's slugs; it goes stale
  the first time an editor renames an article, and the table fills with 40 rows nobody
  will ever look at again. Rules are reserved for what genuinely needs a human decision.
- **Web-server (Traefik) redirects.** Not editable without a deploy, and Traefik cannot
  see whether a page exists.
