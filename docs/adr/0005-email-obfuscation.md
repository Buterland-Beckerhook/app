# ADR 0005 — E-mail obfuscation with CSS decoys, not JavaScript assembly

**Status:** Accepted (2026-07-26)

## Context

The pre-Phoenix site protected published addresses with an anti-spam mail link
(`RELAUNCH_PLAN.md` still lists a `MailLink.svelte` as "wie bisher"). The rewrite
dropped it. Today the only live route onto a public page is the `{{ role.email }}`
placeholder, which `Bbh.Placeholders` substitutes in the clear — and editors can put
a `mailto:` link into any rich-text body, which `Bbh.Html.sanitize/1` allows and
`BbhWeb.Format` passed through untouched. `Webseite Konzept.md` wants public
addresses on `/kontakt`, so the exposure is about to grow.

The classic solution — build the link in JavaScript, put a `foo (at) bar (dot) de`
fallback in `<noscript>` — has aged badly. The `(at)`/`(dot)` spelling is a known
pattern that harvesters translate back, it cannot be copied, and screen readers make
a mess of it.

For the Impressum there is a second constraint: § 5 DDG wants the address "leicht
erkennbar, unmittelbar erreichbar und ständig verfügbar". Whether obfuscation
satisfies that is contested in Germany. An address that only exists once JavaScript
has run is the weakest position to defend.

## Decision

Render the address split into chunks, with decoy elements woven in between that a
`display: none` rule hides (`BbhWeb.EmailObfuscation`, `.eml-x` in `app.css`):

```html
<a href="/kontakt" data-eml=""><span class="eml"
  ><span>vorst</span><span class="eml-x" aria-hidden="true">Qkz</span
  ><span>and@buter</span><span class="eml-x" aria-hidden="true">NwtR</span
  ><span>land-beckerhook.de</span></span></a>
```

**No JavaScript is required to read it.** With CSS the text is the address, it is
selectable, and it copies cleanly — `display: none` content is left out of a
selection and out of the accessibility tree, so what a sighted user copies and what
a screen reader announces are both correct. That is what makes the same treatment
defensible on the Impressum: the address is there, always, JS or not. Applied
uniformly; no exception page.

That argument only holds for the default shape. `<.email_link label={...}>` moves the
address into a `display: none` container — invisible to sighted users *and* absent from
the accessibility tree, reachable only once JavaScript has run. **Do not use the `label`
variant on the Impressum**; it is for places where a contact address is a convenience,
not a legal obligation.

**The decoy invariant.** `fragments/1` guarantees one decoy strictly inside the
local part and one strictly inside the domain, never at either end. A harvester that
deletes the tags and regexes the remainder therefore does not come up empty — it
comes up with `vorstQkzand@buterNwtRland-beckerhook.de`: syntactically valid, and on
some other domain than ours. The miss reads as a hit, so it is never retried by hand,
and the harvester poisons its own list. The decoy in the *domain* carries that
property; junk confined to the local part would send the spam to an undeliverable
mailbox on our own domain instead of somebody else's problem.

What the code guarantees is "wrong", not "unregistered". When the cut falls before the
last dot the result is a registrable domain (`info@exampleQkzd.com`) — with 3–8 random
letters, one that is live is not worth planning around.

Split points and decoy strings are random per render — no fixed pattern across pages.

**No encoded payload.** `assets/js/mail.js` reassembles the address out of the DOM by
skipping `.eml-x`, and swaps the anchor's `href` from `/kontakt` to `mailto:`. There
is deliberately no base64/ROT13/XOR blob and no key: a blob is a single visible
target that invites "decode every data attribute", and it would add a second
representation of the address to keep in sync. The upgrade happens on the first
interaction (`pointerdown` / `touchstart` / `focusin`), not on load, so a headless
scraper that renders the page and collects hrefs gets the contact form.

`aria-hidden="true"` on the decoys is redundant next to `display: none` and does give
a CSS-free reader a tell. It stays for the contexts where our stylesheet is not
applied — reader mode, print paths, copied markup. A scraper sophisticated enough to
act on `aria-hidden` renders CSS anyway, so nothing is really given away.

**One choke point.** `BbhWeb.Format.render_richtext/1` runs `rewrite/1` last, over the
finished HTML, so it covers editor-authored `mailto:` links, addresses typed straight
into the copy, and whatever `{{ role.email }}` resolved to — in one place, with no
editor discipline required. Search snippets get the same treatment in
`SiteComponents.mark_headline/1`; the index is built from the stored body before
placeholders resolve, so that is the second way out onto a public page.

A bare address in running text becomes inline markup, not a link. It may already sit
inside an anchor and anchors cannot nest; editors who want it clickable set a real
link in the editor.

The rewrite assumes `Bbh.Html.sanitize/1` re-serialized the stored HTML: double-quoted
attributes and a balanced `</a>`. An unbalanced or single-quoted anchor falls through
to the tag branch and keeps its address in the clear.

`Bbh.Html.RichScrubber` permits a `class` attribute on `<span>` and `<a>` so Quill can
store alignment. What keeps that from becoming a hole here is `sanitize/1` narrowing
the values to `@allowed_classes` — an editor writing `class="eml-x"` by hand loses the
attribute, so stored content cannot hide text behind our decoy rule.

## Consequences

- Addresses are still stored in the clear. The protection is a render-time concern —
  nothing to migrate, and turning it off is deleting one pipeline step.
- **A scraper driving a real browser still gets the address** via `innerText`. That is
  the price of keeping it readable without JavaScript, and it is the trade-off we
  chose. The second line stays what it already is: the Altcha-protected contact form
  (ADR 0003) and server-side spam filtering.
- The markup is chattier — five `<span>`s per address. Irrelevant at this scale.
- Every rendered address differs between requests. Nothing caches rendered HTML
  today; if that changes, the randomness is simply frozen per cached copy, which
  costs nothing.
- Known gap in search snippets: a `@@M@@` match marker landing inside an address
  keeps it in the clear, because the pattern no longer matches.
- **Not covered: the public iCal feed.** `Bbh.ICal` puts the stripped event body into
  `DESCRIPTION` (`ical.ex:71`), and `/termine/abo.ics` is unauthenticated. An address in
  an event body therefore leaves the site in the clear through a machine-readable
  endpoint. Obfuscation is not the answer there — a calendar client shows the raw text,
  so decoys would reach the reader. Either accept it (a calendar description is a
  legitimate place for contact details, and the feed is a niche harvesting target) or
  strip addresses out of `DESCRIPTION` entirely. Deliberately left open.
- `SiteComponents.person_table/1` does not render addresses today. If the
  `display_style: "cards"` renderer is ever built out, it must go through
  `email_link/1`.
- No JavaScript test runner exists in this repo, so `mail.js` is not covered directly.
  The contract it depends on — drop `.eml-x`, join the rest, get the address — is
  asserted in `test/bbh_web/email_obfuscation_test.exs`, which leaves only the DOM
  glue uncovered.
