// Aufnahmeantrag as PDF, filled from a Postfach membership ticket (Bbh.Tickets.Pdf).
// Layout follows the paper form; the data comes from data.json next to this file, written
// by the app into a private temp dir and removed after the run. Never stored.
//
// Differences from the paper form, on purpose:
//   - SEPA mandate and privacy text come from Bbh.Membership — the same text the
//     online form shows (the mandate in the paper form's wording), so the record states
//     what the applicant actually accepted.
//   - No consent checkboxes: the online form asks for none (Art. 6(1)(b) GDPR).
//   - "Ort, Datum / Unterschrift" is replaced by the electronic submission record.

#let d = json("data.json")

#set document(title: "Aufnahmeantrag " + d.reference, author: "Schützenverein Buterland-Beckerhook e.V.")
#set page(
  paper: "a4",
  margin: (x: 15mm, top: 12mm, bottom: 16mm),
  footer: context [
    #set text(7pt, fill: rgb("#777777"))
    #grid(
      columns: (1fr, auto),
      [Erzeugt am #d.generated_at von #d.generated_by · #d.reference],
      [Seite #counter(page).display() von #counter(page).final().first()],
    )
  ],
)
#set text(font: "Barlow", size: 9pt, fill: rgb("#202020"), lang: "de")
#set block(spacing: 7pt)

#let primary-color = rgb("#0e822f")
#let rule = line(length: 100%, stroke: 0.4pt + rgb("#cccccc"))

// A labelled value on a line, like a filled-in field of the paper form. A stack, so
// paragraph spacing doesn't pull label, value and line apart.
#let field(label, value, note: none) = stack(
  text(8pt)[#label],
  v(6pt),
  box(height: 10pt)[#text(10pt)[#value]],
  v(1.5pt),
  rule,
  ..if note != none { (v(2pt), text(6pt)[#note]) },
)

#let section(title, body) = rect(
  width: 100%,
  fill: rgb("#f7faf7"),
  stroke: 0.5pt + primary-color.lighten(50%),
  radius: 3pt,
  inset: 6pt,
)[
  #text(9.5pt, weight: "bold", fill: primary-color)[#title]
  #v(4pt)
  #body
]

// Header
#grid(
  columns: (1fr, auto),
  gutter: 10mm,
  align: (left + bottom, right + horizon),
  [#text(16pt, weight: "bold", fill: primary-color)[Aufnahmeantrag]],
  image("logo_sv_lng_nb.svg", height: 22mm),
)

#v(-2mm)
#line(length: 100%, stroke: 0.5pt + primary-color)
#v(1mm)

#text(8pt)[#d.fee_note]

#v(1.5mm)

#if d.flags.len() > 0 [
  #rect(width: 100%, fill: rgb("#fff6e0"), stroke: 0.5pt + rgb("#d9a400"), radius: 3pt, inset: 6pt)[
    #text(8pt, weight: "bold")[Hinweise (bitte prüfen)]
    #for flag in d.flags [
      #linebreak() #text(8pt)[#flag]
    ]
  ]
  #v(1.5mm)
]

// 1. Persönliche Daten
#section[1. Persönliche Daten des Antragstellers][
  #grid(
    columns: (1fr, 1fr),
    gutter: 6mm,
    field[Nachname:][#d.nachname],
    field[Vorname:][#d.vorname],
  )
  #v(1pt)
  #grid(
    columns: (2fr, 1fr),
    gutter: 6mm,
    field[Straße und Hausnummer:][#d.strasse],
    field[Geburtsdatum:][#d.geburtsdatum],
  )
  #v(1pt)
  #grid(
    columns: (2fr, 2fr, 1fr),
    gutter: 6mm,
    grid(
      columns: (22mm, 1fr),
      gutter: 4mm,
      field[PLZ:][#d.plz],
      field[Ort:][#d.ort],
    ),
    field[E-Mail-Adresse:][#d.email],
    field(note: if d.member_number == "" { "wird vom Verein eingetragen" })[Mitgliedsnummer:][
      #d.member_number
    ],
  )
  #v(1pt)
  #text(8pt)[Kinder unter #d.max_child_age Jahren:]
  #v(2pt)
  #let children = if d.children.len() > 0 { d.children } else { ((vorname: "–", geburtsdatum: ""),) }
  #for (i, child) in children.enumerate() [
    #grid(
      columns: (2fr, 1fr),
      gutter: 6mm,
      field(if i == 0 { "Vorname:" } else { "" })[#child.vorname],
      field(if i == 0 { "Geburtsdatum:" } else { "" })[#child.geburtsdatum],
    )
    #v(1pt)
  ]
]

#v(1.5mm)

// 2. SEPA-Lastschriftmandat
#section[2. SEPA-Lastschriftmandat][
  #grid(
    columns: (140pt, 1fr),
    gutter: 2mm,
    text(8pt)[Gläubiger-Identifikationsnummer:], text(8pt)[#d.creditor_id],
    text(8pt)[Mandatsreferenz:], text(8pt)[#d.mandate_reference],
  )
  #v(4pt)
  #grid(
    columns: (1fr, 1fr),
    gutter: 6mm,
    field[Kontoinhaber:][#d.kontoinhaber],
    field[Kreditinstitut:][#d.kreditinstitut],
  )
  #v(1pt)
  #grid(
    columns: (2fr, 1fr),
    gutter: 6mm,
    field[IBAN:][#text(font: "DejaVu Sans Mono", 9pt)[#d.iban]],
    field[BIC:][#d.bic],
  )
  #v(1pt)
  #text(7pt, fill: rgb("#555555"))[#d.mandate_text \ #d.mandate_note]
]

#v(1.5mm)

// 3. Datenschutz
#section[3. Datenschutz][
  #text(7.5pt)[
    #d.privacy_note
    Abrufbar unter #link("https://buterland-beckerhook.de/datenschutz")[buterland-beckerhook.de/datenschutz].
    Die Verarbeitung der Daten ergibt sich aus der Mitgliedschaft (Art. 6 Abs. 1 lit. b DSGVO);
    eine Einwilligung wurde im Online-Formular nicht abgefragt.
  ]
]

#v(1.5mm)

// 4. Instead of "Ort, Datum / Unterschrift"
#section[4. Elektronisch übermittelt][
  #set text(8pt)
  #grid(
    columns: (auto, 1fr, auto, 1fr),
    row-gutter: 3pt,
    column-gutter: 3mm,
    [Übermittelt am:], [#d.submitted_at],
    [SEPA-Lastschriftmandat erteilt:], [#d.sepa_mandate],
    [IP-Adresse:], [#d.client_ip],
    [Spam-Schutz (Altcha) geprüft:], [#d.altcha_verified],
    [Vorgang:], [#d.reference],
    [Formularversion:], [#text(font: "DejaVu Sans Mono")[#d.form_version]],
  )
]
