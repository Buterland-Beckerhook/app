# Content plan – what the site still needs

Status: October 2026. Compares three sources against the current database:

1. the iframe-era site (`../buterland-beckerhook-old/`, until ~2018/2020),
2. the Hugo site (`https://old.buterland-beckerhook.de/`, `../buterland-beckerhook/`),
3. the current dev snapshot (`pages`, `articles`, `people`, `thrones`).

The researched facts live in [`verein/`](verein/README.md) (German); this file only
plans what to build and enter. Articles are complete (all Hugo articles are migrated);
everything below is pages, structured data, and optional archive material.

## What already exists

Pages under *Der Verein*: Über uns → Vereinsgeschichte, Insignien, Vereinslokal,
Ehrenmal · Vorstand → Geschäftsführender Vorstand, Präsidenten · Offiziere → Führung des
Offizierscorps, Die Chefs der Offiziere · Jungschützen · Mitglied werden.
Thron: 86 kings 1909–2026, kaisers 1984 and 2009, Stadtkaiser 2025,
Jungschützenkönig 2026. 169 articles; before 2018 only throne articles.

Everything from the Hugo *Der Verein* menu is covered. The only Hugo page not carried
over is `verein/about/schuetzenfest` (two sentences about the Festplatz) – fold it into
„Über uns". The Hugo `orga/ausschuesse/*` pages were lorem-ipsum drafts; nothing to take.

## 1. Must have

### 1.1 Pokalsieger (new)

Data: [`verein/pokalschiessen.md`](verein/pokalschiessen.md) – five trophies, winners
1969–2026, with gaps (2021/2022, Biwakpokal 2018 and 2022–2026, early years).

Recommendation: **structured data, not a richtext table.** A new year is added every
January (and every May for the Biwakpokal), the table is ~60 rows × 5 columns, and a
structured source gives per-person counts and a mobile-friendly layout for free.

- Schema in `Bbh.Club`: `trophies` (name, slug, since, eligibility text, origin,
  sort_order) and `trophy_wins` (trophy_id, year, winner name, rings nullable, note
  nullable; unique on trophy + year). Winners stay plain names, like `thrones` does –
  no FK to `people`.
- Admin CRUD under `/admin` (a „Pokale" tab next to the people admin).
- Content block „Pokalsieger" (like `PersonList`), so the list sits on a normal page
  with editor-written intro text: year × trophy matrix, newest first; optionally a
  „Rekordsieger" box.
- Page: *Der Verein → Schießriege & Pokale* (`/verein/pokale`), intro from the
  Schießriege / trophy texts.
- One-off import from the Markdown table (seed script or a mix task) – after the
  name spellings in „Offene Punkte" are settled.
- Search: index the page; the winner names make it findable by surname.

Cheaper fallback: one richtext page with a Markdown table. Works today, but every
January means editing a big HTML table by hand.

### 1.2 Ehrenmitglieder page (new)

Data: [`verein/ehrenmitglieder.md`](verein/ehrenmitglieder.md) – 3 honorary chairmen,
~34 honorary members, 16 known dead, portraits for 17 in the old site.

Decided (2026-10-25):

- **`honorary_since` (year) replaces the `honorary_member` boolean.** Set = honorary
  member, empty = not. Migration maps known years (see the doc); an unknown year is
  stored as **1900** (placeholder, not rendered). The page stays unpublished until the
  data is complete; death dates may come from the local paper's archive.
- **Deceased = `death_date` set.** `birth_date` / `death_date` become real `date`
  columns with the date picker; new `birth_place` / `death_place`. Cards render as today:
  long German date, „in <Ort>" when present.
- **No duplicate people.** Hermann Lewing keeps only his last office (Präsident
  1955–1958); the Oberst years go into his biography.
- PersonList gets a living/deceased split for the honorary list.

Page: *Der Verein → Über uns → Ehrenmitglieder* (`/verein/ueber-uns/ehrenmitglieder`),
intro + honorary chairmen + living + deceased (with † date) + the 1984 group photo.

Before publishing: ask the Vorstand who has died since 2020, and get consent for
photos/dates of living members (see open points in the doc).

## 2. Data fixes found during the review

| Where | Problem | Fix |
|---|---|---|
| `people` Gerhard Gleis-Preister (Präsident) | `year_end` = 2018 | **1998** (handed over 21.11.1998) |
| `people` Wilhelm Hoff | `birth_date` = „* 21. Juli 1942 …" | drop the leading „* " |
| `people` Theodor Eimann, Heinrich Lammers, Heinrich Pieper, Wilhelm Hoff | `honorary_member` = false, but Ehrenvorsitzender / Ehrenmitglied | superseded: set `honorary_since` in the 1.2 migration |
| `thrones` 1930/31 Heinrich Meyer | article exists, **no throne row** – missing from `/thron` | add the throne row |
| `thrones` Stadtkaiser | only 2025 of our four | add **2000 Ludger Bußjan / Birgit Theissing**, **2011 Andreas Lösing / Renate Büscher**, **2022 Martin Schreiber / Maria Oude Lansink** – each needs an article (`thrones.article_id` is required); drafts created in prod via MCP. Reports may still be found in the WN archive. |
| `thrones` 1911–1938 | eleven kings and the **1922 Kaiser (Gerhard Agten)** missing – the Festschrift 1959 lists them all | `20261025130000_add_early_thrones_from_festschrift_1959` adds them like the existing early thrones (published „Nur Thron-Anzeige“); the Kaiser 1922 article is a draft in prod, the migration attaches his throne |
| `thrones` 1935, 1958 | Festschrift says „Franz Stipinzky“ and (twice) „Bernhard Heßling“; the site has „Wladislaus Stypinski“ and „Bernhard Hesselink“ | not changed – needs a decision (see `verein/festschrift-1959.md`) |
| Thron menu | linked Kaiser articles even while still drafts (dead link) | only published Kaiser articles are linked |
| `verein/vereinsgeschichte.md` | Ehrenmitglieder table had unverified claims | moved and corrected in `verein/ehrenmitglieder.md` |

## 3. Should have – *Der Verein* pages

| Page | Source | Note |
|---|---|---|
| **Ausschüsse** (Kinderfest, Senioren, Schießriege, Festausschuss) | old `ausschue/*.html`, [`verein/jahreslauf-und-brauchtum.md`](verein/jahreslauf-und-brauchtum.md) | One page with sections or a parent with children. Current members/contacts from the Vorstand. Schießriege can be the intro of the Pokale page. |
| **Unser Jahr** (Jahreslauf) | `jahreslauf-und-brauchtum.md` | Short page: what happens when; links to `/termine`. Optional, could be a section of „Über uns". |
| **Vogelbau / Brauchtum** | old `sonstiges/vogelbau.html` | Fits as a section on Insignien or a small page. |
| **Königs-/Königinnentreffen, Stadtkaiser, Euregio** | old `thron/*.html` | Better as articles (section 4) linked from `/thron`. |

Skip: Satzung (decided: available from the Vereinsregister), old „Partner"/links page (dead URLs), guestbook, LAGA 2003 teaser,
„Veranstaltungsorte" map (event pages already embed the map).

## 4. Nice to have – archive articles from the iframe era

All are real reports not yet on the site; each becomes an article with its original
year (`date_published` in that year). Text extraction: Latin-1 HTML, strip markup.

| Topic | Years | Count |
|---|---|---|
| Winterfest reports | 2002, 2004–2017 | 15 |
| Stadtschützenfest / Stadtkaiser | 2000, 2005, 2011 | 3 (2000 and 2011 double as throne articles, see §2) |
| Königstreffen | 2010, 2015 | 2 |
| Königinnentreffen | 2003, 2011 | 2 |
| Euregio-Schützenfest | 2003 | 1 |
| Stadtmeisterschaften Luftdruckwaffen (we hosted) | 2006 | 1 |
| Vogelbauer Alfons Diekmann → Hubert Winking | ~2012 | 1 |
| Frauenfest | 2007, 2016 | 2 |
| Jugendbiwak | 2002, 2005, 2010, 2016 | up to 4 |
| Jungschützen (Fußballturnier 2005/2006, Paintball, Versammlung 2006, Gewehre) | 2005–2006 | ~5, check worth |
| Säuberungsaktion | ? | 1 |

Not worth migrating: JHV pages (only invitations/agenda), yearly programmes and
invitations 2002–2018, Termine pages.

Archive articles must **not** push – and today they would: `Content.articles_pending_notification/0`
picks up every published article with `date_published <= now` and no `notified_at`,
however old. Import them with `notified_at` set (seed/mix task), or teach the notifier
to skip articles dated well before their publish moment (e.g. older than 7 days), before
publishing ~35 old articles. Not urgent today (no subscribers besides the maintainer), but
it bites as soon as members subscribe.

## 5. Optional – photo albums 2009–2016

The old site has ~4,000 photos (Schützenfest 2009–2016: Vogelschießen, Festumzug,
Königs- and Krönungsball, Kinderfest; Jubiläum 2009; Jugendbiwak). The media library
has 589 items. A full import is not sensible on the small shared host; a curated pick
(10–20 per festival, as galleries on the throne article of that year) is. Low priority.

## 6. Questions for the Vorstand

1. Pokalsieger 2021/2022, Biwakpokal 2018 and 2022–2026, Juniorenpokal 2026, early years
   (engravings on the trophies?).
2. Ehrenmitglieder: deaths since 2020, appointment years before 2018, consent for photos.
3. Was Gerhard Gleis-Preister Ehrenpräsident? Was Erich Zgodda Ehrenmitglied?
4. Current members of the Ausschüsse; does the Jugendbiwak still exist?

## Suggested order

1. Data fixes (§2) – done in `20261025120000_fix_club_data` plus two Stadtkaiser
   article drafts (2000, 2011, 2022) created in prod; publish them after the deploy. Honorary
   flags are handled by step 2 instead.
2. Ehrenmitglieder: decide the role/dedupe question, add `honorary_since` + grouping,
   enter data, publish once the Vorstand has answered.
3. Pokalsieger: schema + admin + block + import, page under *Der Verein*.
4. Ausschüsse page.
5. Archive articles (push-safe), then curated photos.
