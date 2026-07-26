- [x] 'Veroeffentlich am' nicht resetten bei Aenderung. 'Date Modified' bei Aenderung aktualisieren.
- [x] 'use_as_article_image' sollte nur bei einem Bild pro artikel moeglich sein, z.b. biwak 2026.
- [x] tabellenname 'images' ueberdenken, ist verknuepfung zu articles
- [x] Block 'bildkarte' erlaubt kein Einfuegen von bildern (fehlt generell media -> seiten verknuepfung?)
- [x] Bilder nur loeschen, wenn nicht in verwendung
- [x] Auch pdf als medien zulassen
- [x] Medien gallerie: Ordner erlauben (mit unterordnern, 2 ebenen), damit medien in ordnern einsortiert werden koennen
- [x] Bild title, description, copyright in media-gallerie editierbar (passt zu DB design)
- [x] Artikel: 'Veroeffentlicht am' Reset-Bug behoben; einheitlicher flatpickr-Picker/Format wie Termine
- [x] Artikel- & Termin-Uebersicht (alle Admin-Listen): Paging, Namensfilter, Spalten-Sortierung
- [x] 'Status'-Feld in Admin-Tabellen vereinheitlicht (gemeinsame <.status_badge> Komponente)
- [x] Person: eMail-Feld ergaenzt
- [x] Personendaten im Text referenzierbar: {{ rolle.feld }} (aktuell/letzter Amtsinhaber, nach 'Amt bis')
- [x] Trix: Datei aus Mediathek einfuegbar (Bild -> <img>, sonst Datei-Link)
- [x] Mediathek-Editor: Bilder in 90-Grad-Schritten drehen (schreibt das Original, EXIF-Lage inklusive)
- [x] Bildtexte nur noch in der Mediathek: Titel, Bildunterschrift, Beschreibung (Alt-Text), Copyright.
      Am Artikelbild bleiben nur 'Bildunterschrift anzeigen' (Standard an), Thronbild, Sortierung
- [x] Galerie im Artikel beachtet die Sortierung (preload_order auf article_images/gallery_files)
- [x] Bildunterschrift + Copyright werden angezeigt: schmale, gedaempfte Zeile unter dem Bild
      (Copyright rechts); bei Galeriebildern erst beim Vergroessern in der Lightbox
- [x] Seiten-Edit: Galerie-Block erlaubt Bilder waehlen, sortieren, entfernen
- [x] Bildauswahl beachtet die Ordnerstruktur — ein gemeinsamer Picker fuer Artikel, Bild-Karte,
      Galerie und Trix (Ordner-Navigation, Suche ueber alle Ordner)
