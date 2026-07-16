# Relaunch buterland-beckerhook.de

## Stack

| Komponente | Technologie |
|---|---|
| **CMS** | Directus (Self-hosted, PostgreSQL) |
| **Frontend** | SvelteKit (5) (Node-Adapter, SSR) |
| **CSS** | TailwindCSS 4 |
| **Push-Notifications** | Web Push API + Service Worker |
| **Deployment** | Docker Compose (Directus + PostgreSQL + SvelteKit + Caddy) |
| **Repository** | Monorepo (`frontend/`, `docker/`, `migration/`) |

## Repo-Struktur (Monorepo)

```
buterland-beckerhook/
├── frontend/                    # SvelteKit App
│   ├── src/
│   │   ├── lib/
│   │   │   ├── components/      # Svelte-Komponenten
│   │   │   ├── server/          # Server-only Utilities (Directus Client, Push etc.)
│   │   │   └── utils/           # Shared Utilities
│   │   ├── routes/              # SvelteKit Pages & API Routes
│   │   └── service-worker.ts    # Push-Notification Service Worker
│   ├── static/                  # Favicon, manifest.json, PWA Icons
│   ├── svelte.config.js
│   ├── tailwind.config.ts
│   ├── package.json
│   └── Dockerfile
├── migration/                   # Content-Migrations-Skript
│   ├── src/
│   │   ├── import-articles.ts
│   │   ├── import-events.ts
│   │   ├── import-thrones.ts
│   │   ├── import-locations.ts
│   │   ├── import-people.ts
│   │   ├── import-pages.ts
│   │   └── import-media.ts
│   ├── package.json
│   └── tsconfig.json
├── docker/
│   ├── caddy/
│   │   └── Caddyfile
│   └── directus/
│       └── extensions/          # Directus Extensions (Hooks, Endpoints)
├── docker-compose.yml
├── docker-compose.dev.yml       # Dev-Overrides (Ports, Volumes, Hot-Reload)
├── .env.example
├── .gitignore
└── README.md
```

---

## Phase 1: Infrastruktur & CMS Setup

### 1.1 Docker Compose

Services:

- **postgres** — PostgreSQL 16 Alpine, persistentes Volume
- **directus** — Directus latest, verbunden mit PostgreSQL
  - Uploads-Volume für Medien
  - VAPID Keys für Web Push als Environment Variables
- **frontend** — SvelteKit mit Node-Adapter
  - Zugriff auf Directus über internes Docker-Netzwerk
- **caddy** — Reverse Proxy mit automatischem SSL
  - `buterland-beckerhook.de` → frontend:3000
  - `cms.buterland-beckerhook.de` → directus:8055

Dev-Setup (`docker-compose.dev.yml`):
- Directus auf `localhost:8055` (direkt erreichbar)
- Frontend auf `localhost:5173` (Vite Dev Server, nicht Docker)
- PostgreSQL auf `localhost:5432` (für Migration-Skript)

### 1.2 Directus Content-Modell

#### Collection: `articles`
| Feld | Typ | Pflicht | Notizen |
|---|---|---|---|
| `id` | UUID, PK | auto | |
| `status` | Dropdown | ja | `draft`, `published`, `archived` |
| `title` | String | ja | |
| `subtitle` | String | | |
| `slug` | String, unique | ja | Auto-generiert aus Titel |
| `date_published` | DateTime | ja | Veröffentlichungsdatum |
| `author` | String | | |
| `tags` | JSON (Tags Interface) | | z.B. `["Thron", "Schützenfest"]` |
| `body` | WYSIWYG / Markdown | | Artikeltext |
| `is_throne_article` | Boolean | | default: false |
| `no_article` | Boolean | | default: false — nur Thron-Anzeige |
| `aliases` | JSON | | URL-Redirects für Migration |
| `images` | O2M → `article_images` | | Zugehörige Bilder |
| `throne` | O2O → `thrones` | | Thron-Daten (wenn `is_throne_article`) |

#### Collection: `article_images`
| Feld | Typ | Pflicht | Notizen |
|---|---|---|---|
| `id` | UUID, PK | auto | |
| `article` | M2O → `articles` | ja | |
| `image` | File (Directus Files) | ja | |
| `logical_name` | String | | z.B. `thron-1`, `bild-1`, `aspiranten_1-1` |
| `title` | String | | Bildunterschrift |
| `copyright` | String | | Urheber |
| `sort` | Integer | | Reihenfolge |

#### Collection: `thrones`
| Feld | Typ | Pflicht | Notizen |
|---|---|---|---|
| `id` | UUID, PK | auto | |
| `article` | O2O → `articles` | ja | Zugehöriger Artikel |
| `type` | Dropdown | ja | `thron`, `kaiserthron` |
| `years` | String | ja | z.B. "2023-2024", "1909/1910" |
| `king_title` | String | | Regalname: "Gerd X.", "Bernhard I." |
| `king` | String | ja | Bürgerlicher Name des Königs |
| `queen` | String | ja | Name der Königin |
| `moh1` | String | | Ehrendame 1 |
| `moh2` | String | | Ehrendame 2 |
| `loh1` | String | | Ehrenherr 1 |
| `loh2` | String | | Ehrenherr 2 |
| `cupbearer` | String | | Mundschenk |
| `courtmarshal` | String | | Oberhofmarschall |

#### Collection: `events`
| Feld | Typ | Pflicht | Notizen |
|---|---|---|---|
| `id` | UUID, PK | auto | |
| `status` | Dropdown | ja | `draft`, `published`, `canceled` |
| `title` | String | ja | |
| `slug` | String, unique | ja | |
| `start` | DateTime | ja | Event-Beginn |
| `end` | DateTime | | Event-Ende (mehrtägige Events) |
| `location` | M2O → `locations` | | |
| `body` | WYSIWYG / Markdown | | Beschreibung |
| `cancel_reason` | String | | Grund bei Absage |
| `announce` | Boolean | | default: true — öffentlich ankündigen |
| `revision` | Integer | | Versionszähler |
| `enable_ical` | Boolean | | default: true — iCal-Export aktivieren |

#### Collection: `locations`
| Feld | Typ | Pflicht | Notizen |
|---|---|---|---|
| `id` | UUID, PK | auto | |
| `key` | String, unique | ja | `platz`, `dinkelhof`, `gleis`, `none`, `unknown` |
| `name` | String | ja | Anzeigename |
| `street` | String | | |
| `zip` | String | | |
| `city` | String | | |
| `lat` | Float | | GPS Breitengrad |
| `lng` | Float | | GPS Längengrad |
| `maps_url` | String | | Google Maps Link |

#### Collection: `people`
Vorstand und Offiziere in einer Collection mit Gruppen-Feld.

| Feld | Typ | Pflicht | Notizen |
|---|---|---|---|
| `id` | UUID, PK | auto | |
| `group` | Dropdown | ja | `vorstand`, `offiziere` |
| `role` | String | ja | z.B. "Präsident", "Oberst" |
| `role_key` | String | ja | z.B. `praesident`, `oberst` (für Sortierung/Logik) |
| `name` | String | ja | |
| `street` | String | | |
| `city` | String | | |
| `sort_order` | Integer | ja | Reihenfolge innerhalb der Gruppe |

#### Collection: `pages`
Statische Seiten (Impressum, Datenschutz, Verein-Unterseiten etc.)

| Feld | Typ | Pflicht | Notizen |
|---|---|---|---|
| `id` | UUID, PK | auto | |
| `status` | Dropdown | ja | `draft`, `published` |
| `title` | String | ja | |
| `slug` | String, unique | ja | |
| `body` | WYSIWYG / Markdown | ja | |
| `parent` | M2O → `pages` | | Für Hierarchie (z.B. Verein → Unterseiten) |
| `sort_order` | Integer | | |

#### Collection: `push_subscriptions`
| Feld | Typ | Pflicht | Notizen |
|---|---|---|---|
| `id` | UUID, PK | auto | |
| `endpoint` | String | ja | Push-API Endpoint URL |
| `keys_p256dh` | String | ja | Verschlüsselungskey |
| `keys_auth` | String | ja | Auth-Token |
| `categories` | JSON | ja | `["termine", "news"]` |
| `created_at` | DateTime | auto | |
| `last_used` | DateTime | | Letzte erfolgreiche Zustellung |

### 1.3 Directus Rollen

| Rolle | Berechtigungen |
|---|---|
| **Administrator** | Voller Zugriff auf alles |
| **Redakteur** | CRUD auf: articles, events, thrones, article_images, pages. Lesen: locations, people |
| **Public (API)** | Nur Lesen, gefiltert auf `status = published` |

---

## Phase 2: SvelteKit Frontend

### 2.1 Setup

- SvelteKit mit `@sveltejs/adapter-node`
- TypeScript (strict)
- TailwindCSS 4
- `@directus/sdk` für typsichere API-Calls
- Farbschema: Primärfarbe `#0b8d36` (Vereinsgrün)

### 2.2 Seiten (Routes)

```
src/routes/
├── +layout.svelte                    # Navigation, Footer, Push-Opt-In
├── +layout.server.ts                 # Globale Daten (Navigation, aktueller Thron)
├── +page.svelte                      # Homepage
├── +page.server.ts                   #   → nächster Termin, 2 letzte News, Thron
│
├── aktuell/
│   ├── +page.svelte                  # News-Übersicht (paginiert)
│   ├── +page.server.ts               #   → Artikel-Liste mit Pagination
│   └── [slug]/
│       ├── +page.svelte              # Einzelner Artikel
│       └── +page.server.ts           #   → Artikel + Bilder + ggf. Thron
│
├── termine/
│   ├── +page.svelte                  # Kalender + Event-Liste
│   ├── +page.server.ts               #   → Events (aktuelles Jahr + Navigation)
│   ├── abo.ics/
│   │   └── +server.ts               # iCal Abo-Feed (alle Events)
│   └── [slug]/
│       ├── +page.svelte              # Einzelnes Event + Karte
│       ├── +page.server.ts           #   → Event + Location
│       └── event.ics/
│           └── +server.ts            # iCal Einzeldownload
│
├── thron/
│   ├── +page.svelte                  # Thron-Galerie (paginiert)
│   └── +page.server.ts              #   → Throne mit Bildern
│
├── verein/
│   ├── +page.svelte                  # Vereins-Übersicht
│   ├── +page.server.ts
│   ├── [slug]/
│   │   ├── +page.svelte             # Unterseite (About, Vorstand, Offiziere, etc.)
│   │   └── +page.server.ts
│
├── kontakt/
│   ├── +page.svelte                  # Kontaktformular
│   └── +page.server.ts
│
├── impressum/+page.svelte
├── datenschutz/+page.svelte
│
└── api/
    ├── push/
    │   ├── subscribe/+server.ts      # POST: Push-Subscription registrieren
    │   ├── unsubscribe/+server.ts    # POST: Push-Subscription entfernen
    │   └── webhook/+server.ts        # POST: Directus Webhook → Push senden
    └── health/+server.ts             # GET: Health-Check
```

### 2.3 Komponenten

Basierend auf den bisherigen Hugo-Shortcodes und Features:

**Layout:**
- `Navbar.svelte` — Responsive Navigation mit Mobile-Menü
- `Footer.svelte` — Links, Copyright, Git-Info
- `Breadcrumb.svelte` — Brotkrümel-Navigation

**Content:**
- `ArticleCard.svelte` — Artikel-Vorschau (Titel, Datum, Bild, Zusammenfassung)
- `ArticleBody.svelte` — Markdown/Rich-Text Rendering
- `ThroneTable.svelte` — Thron-Mitglieder Tabelle (König, Königin, Hofstaat)
- `ThroneGallery.svelte` — Paginierte Thron-Galerie mit Bildern
- `PeopleTable.svelte` — Vorstand/Offiziere Anzeige

**Media:**
- `ImageSlideshow.svelte` — Bilder-Slideshow (Embla Carousel oder Swiper)
- `ImageGrid.svelte` — Responsives Bilder-Grid
- `ImageLightbox.svelte` — Vollbild-Ansicht (PhotoSwipe 5 oder GLightbox)

**Events:**
- `EventCard.svelte` — Event-Vorschau (Titel, Datum, Ort, Status)
- `EventMap.svelte` — Leaflet-Karte mit Marker
- `YearCalendar.svelte` — Interaktiver Jahreskalender
- `ICalButton.svelte` — Download/Abo Button für iCal

**Interactive:**
- `ContactForm.svelte` — Kontaktformular mit Validierung
- `PushOptIn.svelte` — Push-Notification Opt-In Dialog
- `PushSettings.svelte` — Kategorie-Auswahl (Termine, News)
- `CookieBanner.svelte` — DSGVO-konformer Hinweis (falls nötig)

**Utility:**
- `Alert.svelte` — Info/Warnung/Fehler-Box
- `Pagination.svelte` — Seiten-Navigation
- `DateFormat.svelte` — Deutsche Datumsformatierung
- `MailLink.svelte` — Anti-Spam E-Mail-Link (wie bisher)

### 2.4 Directus SDK Integration

```typescript
// src/lib/server/directus.ts
import { createDirectus, rest, readItems } from '@directus/sdk';

const directus = createDirectus<Schema>(DIRECTUS_URL).with(rest());

// Typisierte API-Calls
export async function getArticles(page: number, limit: number) {
  return directus.request(
    readItems('articles', {
      filter: { status: { _eq: 'published' } },
      sort: ['-date_published'],
      limit,
      offset: (page - 1) * limit,
      fields: ['id', 'title', 'subtitle', 'slug', 'date_published', 'tags',
               { images: ['image', 'title'] }],
    })
  );
}
```

---

## Phase 3: Content-Migration

### 3.1 Migrations-Skript (`migration/`)

TypeScript-basiert, nutzt:
- `gray-matter` — Front-Matter-Parsing der Markdown-Dateien
- `@directus/sdk` — Daten in Directus schreiben
- `glob` — Dateien finden
- `sharp` — Bilder optimieren (optional)

Reihenfolge der Migration (Abhängigkeiten beachten):

1. **Locations** importieren (keine Abhängigkeiten)
2. **People** importieren (Vorstand + Offiziere)
3. **Pages** importieren (statische Seiten)
4. **Articles** importieren (ohne Bilder/Thron-Relationen)
5. **Article Images** hochladen und verknüpfen
6. **Thrones** importieren und mit Artikeln verknüpfen
7. **Events** importieren und mit Locations verknüpfen
8. **PDFs** als Directus-Files hochladen

### 3.2 Body-Transformation

Hugo-Shortcodes im Markdown-Body müssen transformiert werden:

| Hugo Shortcode | Ersatz in Directus |
|---|---|
| `{{< image name="bild-1" >}}` | Directus-Bild-Referenz (Asset-ID) |
| `{{< imageslide name="thron" >}}` | JSON-Block oder Custom-Markup für Slideshow |
| `{{< imagegrid name="..." >}}` | JSON-Block für Grid |
| `{{< thronemembers >}}` | Entfällt — wird vom Frontend aus `thrones`-Relation gerendert |
| `{{< tlink url="..." >}}` | Standard Markdown-Link |
| `{{< pdf name="..." >}}` | Directus-File-Referenz |
| `{{< maillink >}}...{{< /maillink >}}` | Custom-Tag oder Platzhalter |
| `{{< br >}}`, `{{< hr >}}` | HTML `<br>`, `<hr>` |
| `{{< alert >}}` | Custom-Block oder HTML |

Strategie: WYSIWYG-Editor in Directus nutzen, Bilder werden über die
Directus-Oberfläche eingebettet. Bestehender Content wird so weit wie möglich
automatisch transformiert, Rest manuell nacharbeiten.

### 3.3 URL-Mapping

Alte URLs müssen auf neue URLs weiterleiten (SEO):

| Alt (Hugo) | Neu (SvelteKit) |
|---|---|
| `/aktuell/2023/slug-name/` | `/aktuell/slug-name` |
| `/termine/2024/schuetzenfest/` | `/termine/schuetzenfest-2024` |
| `/thron/` | `/thron` |
| `/verein/about/` | `/verein/about` |

Umsetzung: SvelteKit `hooks.server.ts` mit Redirect-Map oder
`+page.server.ts` mit `redirect()`.

---

## Phase 4: Push-Notifications

### 4.1 Ablauf

```
1. Nutzer besucht Seite
2. PushOptIn.svelte fragt: "Möchtest du über Termine und News informiert werden?"
3. Nutzer wählt Kategorien (Termine / News / beides)
4. Browser fragt nach Notification-Permission
5. Service Worker registriert sich, erstellt PushSubscription
6. Frontend sendet Subscription an POST /api/push/subscribe
7. Subscription wird in Directus gespeichert (push_subscriptions Collection)

--- Später: Neuer Content wird erstellt ---

8.  Redakteur erstellt neuen Artikel/Termin in Directus
9.  Directus Webhook feuert POST /api/push/webhook
10. SvelteKit-Endpoint liest alle relevanten Subscriptions
11. Sendet Web Push Nachrichten via `web-push` npm-Paket
12. Service Worker empfängt Push-Event
13. Zeigt Notification: "Neuer Termin: Schützenfest 2026"
14. Klick auf Notification → öffnet die relevante Seite
```

### 4.2 VAPID Keys

Web Push benötigt VAPID (Voluntary Application Server Identification) Keys:

```bash
npx web-push generate-vapid-keys
```

- Public Key → Frontend (manifest.json + Service Worker)
- Private Key → Backend (Environment Variable, NIEMALS committen)

### 4.3 Service Worker (`src/service-worker.ts`)

```typescript
self.addEventListener('push', (event) => {
  const data = event.data?.json();
  event.waitUntil(
    self.registration.showNotification(data.title, {
      body: data.body,
      icon: '/images/manifest/icon-192x192.png',
      badge: '/images/manifest/icon-96x96.png',
      data: { url: data.url },
    })
  );
});

self.addEventListener('notificationclick', (event) => {
  event.notification.close();
  event.waitUntil(clients.openWindow(event.notification.data.url));
});
```

---

## Phase 5: Deployment

### 5.1 Docker Compose (Produktion)

```yaml
services:
  postgres:
    image: postgres:16-alpine
    restart: unless-stopped
    volumes:
      - postgres_data:/var/lib/postgresql/data
    environment:
      POSTGRES_DB: directus
      POSTGRES_USER: ${DB_USER}
      POSTGRES_PASSWORD: ${DB_PASSWORD}

  directus:
    image: directus/directus:latest
    restart: unless-stopped
    depends_on: [postgres]
    volumes:
      - directus_uploads:/directus/uploads
      - ./docker/directus/extensions:/directus/extensions
    environment:
      DB_CLIENT: pg
      DB_HOST: postgres
      DB_PORT: 5432
      DB_DATABASE: directus
      DB_USER: ${DB_USER}
      DB_PASSWORD: ${DB_PASSWORD}
      SECRET: ${DIRECTUS_SECRET}
      ADMIN_EMAIL: ${ADMIN_EMAIL}
      ADMIN_PASSWORD: ${ADMIN_PASSWORD}
      PUBLIC_URL: https://cms.buterland-beckerhook.de
      WEBHOOKS_ENABLED: "true"

  frontend:
    build:
      context: ./frontend
      dockerfile: Dockerfile
    restart: unless-stopped
    depends_on: [directus]
    environment:
      DIRECTUS_URL: http://directus:8055
      DIRECTUS_TOKEN: ${DIRECTUS_STATIC_TOKEN}
      PUBLIC_SITE_URL: https://buterland-beckerhook.de
      VAPID_PUBLIC_KEY: ${VAPID_PUBLIC_KEY}
      VAPID_PRIVATE_KEY: ${VAPID_PRIVATE_KEY}
      VAPID_SUBJECT: mailto:${ADMIN_EMAIL}

  caddy:
    image: caddy:2-alpine
    restart: unless-stopped
    ports:
      - "80:80"
      - "443:443"
    volumes:
      - ./docker/caddy/Caddyfile:/etc/caddy/Caddyfile
      - caddy_data:/data
      - caddy_config:/config

volumes:
  postgres_data:
  directus_uploads:
  caddy_data:
  caddy_config:
```

### 5.2 Caddyfile

```caddyfile
buterland-beckerhook.de {
    reverse_proxy frontend:3000
}

cms.buterland-beckerhook.de {
    reverse_proxy directus:8055
}
```

### 5.3 CI/CD (GitHub Actions)

```
Push auf main
  → Lint + Type-Check
  → Docker Images bauen (frontend)
  → Push zu Container Registry
  → Deploy auf Server (docker compose pull && docker compose up -d)
```

### 5.4 Backup-Strategie

- PostgreSQL: Täglicher `pg_dump` via Cron → S3 oder lokaler Speicher
- Directus Uploads: Volume-Backup
- Schema: Directus Schema-Snapshot im Repo (`npx directus schema snapshot`)

---

## Phase 6: Feinschliff

### 6.1 SEO
- Meta-Tags (title, description, og:image) pro Seite
- `sitemap.xml` via SvelteKit
- `robots.txt`
- Structured Data (JSON-LD) für Events

### 6.2 Analytics
- Matomo Integration (self-hosted bei `matomo.verst.eu`)
- Cookieless Tracking, DoNotTrack respektieren
- Opt-Out Möglichkeit auf Datenschutz-Seite

### 6.3 Performance
- Bilder: WebP/AVIF via Directus Asset-Transformationen
- Responsive Images (`srcset`) automatisch
- SvelteKit Preloading (`data-sveltekit-preload-data`)
- Lazy-Loading für Bilder und Karten

### 6.4 Barrierefreiheit (a11y)
- Semantisches HTML
- ARIA-Labels wo nötig
- Tastatur-Navigation
- Kontrast-Prüfung

### 6.5 DSGVO
- Datenschutzerklärung aktualisieren (Directus, Web Push erwähnen)
- Kontaktformular: Einwilligung vor Absenden
- Push-Notifications: Explizites Opt-In
- Matomo: Cookieless, Opt-Out
- Kein Google Fonts CDN → Fonts lokal hosten

### 6.6 iCal
- Abo-Feed: `webcal://buterland-beckerhook.de/termine/abo.ics`
- Einzelne Events als Download
- Kompatiblität: Apple Calendar, Google Calendar, Outlook
- `X-PUBLISHED-TTL:P1W` (wöchentliche Aktualisierung)

---

## Zeitschätzung

| Phase | Aufwand | Abhängigkeit |
|---|---|---|
| 1. Infrastruktur & CMS | 2-3 Tage | — |
| 2. SvelteKit Frontend | 5-8 Tage | Phase 1 |
| 3. Content-Migration | 2-3 Tage | Phase 1 |
| 4. Push-Notifications | 1-2 Tage | Phase 2 |
| 5. Deployment | 1 Tag | Phase 1-4 |
| 6. Feinschliff | 2-3 Tage | Phase 2 |
| **Gesamt** | **~13-20 Tage** | |

Phase 2 und 3 können teilweise parallel laufen.

---

## Offene Entscheidungen

- [ ] Domain für CMS: `cms.buterland-beckerhook.de` oder anderer Subdomain?
- [ ] E-Mail-Versand Kontaktformular: eigener SMTP (Mailcow?) oder Service?
- [ ] Matomo: Bestehende Instanz bei `matomo.verst.eu` weiternutzen?
- [ ] Google reCAPTCHA ersetzen? (z.B. Turnstile von Cloudflare, oder Honeypot)
- [ ] Mapbox weiternutzen oder OpenStreetMap-Tiles direkt?
- [ ] Directus Schema als Code (Schema-Snapshots im Repo) oder nur manuell?
