# Deployment (Beta & Prod)

Der Container wird von **GitHub Actions** gebaut und nach **GHCR**
(`ghcr.io/buterland-beckerhook/app`) gepusht. Der Server **baut nicht selbst** — er zieht
das fertige Image nur noch.

- Build-Workflow: `.github/workflows/build.yml` — läuft bei Push auf `feat/phoenix-rewrite`
  und per „Run workflow" (workflow_dispatch). Tags: `:beta` (rollierend) + `:sha-XXXXXXX`
  (unveränderlich, für Rollback).
- Ein `docker compose`-Stack (`deploy/compose.yml`) bedient **Beta und Prod** — der Unterschied
  steckt komplett in `.env` (`IMAGE`, `SITE_HOST`, `CADDYFILE`, `PHX_HOST`, `BASIC_AUTH_*`).

## Erstmaliges Setup (Beta) auf dem Server

1. **DNS:** A-Record `beta.buterland-beckerhook.de` → Server-IP. Port 80 und 443 müssen
   erreichbar sein (Caddy holt darüber das Let's-Encrypt-Zertifikat).

2. **`deploy/`-Ordner auf den Server bringen** (git clone des Repos oder Ordner kopieren).

3. **`.env` anlegen und ausfüllen:**
   ```sh
   cp .env.example .env
   ```
   - `SECRET_KEY_BASE` erzeugen (läuft ohne Mix direkt im Release-Image):
     ```sh
     docker run --rm ghcr.io/buterland-beckerhook/app:beta \
       bin/bbh eval 'IO.puts(Base.encode64(:crypto.strong_rand_bytes(48)))'
     ```
   - `DB_PASSWORD`, `ALTCHA_HMAC_KEY` (random), `SMTP_*` setzen.
   - **VAPID-Keypair** einmalig erzeugen und stabil halten (Web-Push). Im Dev-Stack via
     `docker compose exec phoenix mix generate.vapid.keys`, oder ohne Mix direkt aus dem Image:
     ```sh
     docker run --rm ghcr.io/buterland-beckerhook/app:beta bin/bbh eval \
       '{pub, priv} = :crypto.generate_key(:ecdh, :prime256v1);
        IO.puts("VAPID_PUBLIC_KEY=" <> Base.url_encode64(pub, padding: false));
        IO.puts("VAPID_PRIVATE_KEY=" <> Base.url_encode64(priv, padding: false))'
     ```
     → `VAPID_PUBLIC_KEY` / `VAPID_PRIVATE_KEY` eintragen.
   - **Basic-Auth-Hash** erzeugen:
     `docker run --rm caddy:2-alpine caddy hash-password --plaintext 'DEIN-PASSWORT'`
     → in `BASIC_AUTH_HASH`. `BASIC_AUTH_USER` frei wählen.
   - Für Beta bereits vorbelegt: `IMAGE=…:beta`, `SITE_HOST`/`PHX_HOST=beta.…`,
     `CADDYFILE=./Caddyfile.beta`.

4. **Bei GHCR anmelden** (Paket ist standardmäßig privat) — einmalig, mit einem Fine-grained PAT
   mit `read:packages`:
   ```sh
   echo <PAT> | docker login ghcr.io -u <github-user> --password-stdin
   ```
   Alternativ das GHCR-Paket in den Package-Settings auf **public** stellen (das Image enthält
   keine Secrets — die kommen erst zur Laufzeit aus `.env`), dann entfällt der Login.

5. **Sicherstellen, dass das `:beta`-Image existiert:** Branch `feat/phoenix-rewrite` pushen bzw.
   den Workflow in GitHub → Actions → „Run workflow" starten und abwarten.

6. **Stack starten:**
   ```sh
   docker compose --env-file .env up -d
   ```
   Postgres und Caddy kommen aus Public-Images, Phoenix aus GHCR. `bin/migrate` läuft beim Start
   automatisch vor dem Server.

### Erfolg prüfen

```sh
docker compose ps                                             # alle Services „healthy"
curl -fsS https://beta.buterland-beckerhook.de/health/liveness # 200 (nach TLS-Ausstellung)
```
Im Browser: `https://beta.buterland-beckerhook.de` → Basic-Auth-Dialog, danach rendert die
Startseite; die Antwort enthält den Header `X-Robots-Tag: noindex, nofollow`.
Admin-Login unter `/users/log-in`.

## Update-Flow („üben")

1. Änderung committen und auf `feat/phoenix-rewrite` pushen → CI baut ein neues `:beta`-Image.
2. Auf dem Server das neue Image ziehen und den Container neu starten:
   ```sh
   docker compose --env-file .env pull phoenix
   docker compose --env-file .env up -d phoenix
   ```
   Migrationen laufen beim Neustart automatisch. Kurze Downtime ist für Beta ok.

### Rollback

Jeder Build ist zusätzlich als unveränderliches `:sha-XXXXXXX` getaggt (Kurz-SHA des Commits,
siehe Actions-Log oder GHCR). Auf einen früheren Stand zurück:
```sh
# in .env:  IMAGE=ghcr.io/buterland-beckerhook/app:sha-abc1234
docker compose --env-file .env pull phoenix
docker compose --env-file .env up -d phoenix
```

## Prod (später)

Denselben Stack für Prod nutzen: eigene `.env` mit `SITE_HOST`/`PHX_HOST=buterland-beckerhook.de`,
`CADDYFILE` weglassen (Default `./Caddyfile` mit www-Redirect, ohne Basic-Auth) und `IMAGE` auf
einen stabilen Tag zeigen lassen.

## Backups

`deploy/backup.sh` — nightly `pg_dump` + Uploads, offsite via Borg (Cron als root). Restore-Runbook
steht im Kopf des Scripts.
