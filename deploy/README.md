# Deployment (Beta & Prod)

The container is built by **GitHub Actions** and pushed to **GHCR**
(`ghcr.io/buterland-beckerhook/app`). The server **does not build** — it only pulls
the finished image. The image is **multi-arch (`linux/amd64` + `linux/arm64`)**; the
prod server is arm64/v8.

- Build workflow: `.github/workflows/build.yml` — runs on push to `feat/phoenix-rewrite`
  and via "Run workflow" (workflow_dispatch). Tags: `:beta` (rolling) + `:sha-XXXXXXX`
  (immutable, for rollback).
- A single `docker compose` stack (`deploy/compose.yml`) serves **Beta and Prod** — the
  difference lives entirely in `.env` (`IMAGE`, `PHX_HOST`, `TRAEFIK_NAME`, `TRAEFIK_RULE`,
  `TRAEFIK_MIDDLEWARES`, `BASIC_AUTH_USERS`).

## Reverse proxy: central Traefik

The stack ships **no reverse proxy of its own** and publishes **no ports**. TLS
(Let's Encrypt), the HTTP→HTTPS redirect, compression, the `www`→apex redirect (Prod)
as well as Basic-Auth + `noindex` (Beta) are all handled by the **central Traefik** on
the host, driven by Docker labels on the `phoenix` service (see `compose.yml`).

Prerequisites: the external Traefik network **`proxy`** already exists on the host, and
Traefik knows the referenced file-provider building blocks `https-redirect@file`,
`secure-tls@file` and the certresolver `le`. (Both are already the case in the existing
setup.)

## First-time setup (Beta) on the server

1. **DNS:** A record `beta.buterland-beckerhook.de` → server IP. Ports 80/443 are already
   served by the central Traefik — this stack opens none itself.

2. **Get the `deploy/` folder onto the server** (git clone the repo or copy the folder).

3. **Create and fill in `.env`:**
   ```sh
   cp .env.example .env
   ```
   - Generate `SECRET_KEY_BASE` (runs without Mix straight from the release image):
     ```sh
     docker run --rm ghcr.io/buterland-beckerhook/app:beta \
       bin/bbh eval 'IO.puts(Base.encode64(:crypto.strong_rand_bytes(48)))'
     ```
   - Set `DB_PASSWORD`, `ALTCHA_HMAC_KEY` (random), `SMTP_*`.
   - **VAPID keypair** — generate once and keep it stable (Web Push). In the dev stack via
     `docker compose exec phoenix mix generate.vapid.keys`, or without Mix straight from the image:
     ```sh
     docker run --rm ghcr.io/buterland-beckerhook/app:beta bin/bbh eval \
       '{pub, priv} = :crypto.generate_key(:ecdh, :prime256v1);
        IO.puts("VAPID_PUBLIC_KEY=" <> Base.url_encode64(pub, padding: false));
        IO.puts("VAPID_PRIVATE_KEY=" <> Base.url_encode64(priv, padding: false))'
     ```
     → enter `VAPID_PUBLIC_KEY` / `VAPID_PRIVATE_KEY`.
   - **Basic-Auth (Beta only)** — generate a bcrypt hash in htpasswd format and put the whole
     `user:hash` into `BASIC_AUTH_USERS`:
     ```sh
     docker run --rm httpd:2-alpine htpasswd -nbB beta 'YOUR-PASSWORD'
     ```
     Do **not** double the `$` in the hash (it arrives as an env variable, not inline in compose.yml).
   - Already pre-filled for Beta: `IMAGE=…:beta`, `PHX_HOST=beta.…`, `TRAEFIK_NAME=bb-beta`,
     `TRAEFIK_RULE=Host(\`beta.…\`)`, `TRAEFIK_MIDDLEWARES=bb-beta-compress,bb-beta-auth,bb-beta-noindex`.

4. **Log in to GHCR** (the package is private by default) — once, with a fine-grained PAT
   that has `read:packages`:
   ```sh
   echo <PAT> | docker login ghcr.io -u <github-user> --password-stdin
   ```
   Alternatively set the GHCR package to **public** in the package settings (the image holds
   no secrets — those come at runtime from `.env`), which removes the login step.

5. **Make sure the `:beta` image exists:** push branch `feat/phoenix-rewrite` or start the
   workflow via GitHub → Actions → "Run workflow" and wait for it.

6. **Start the stack:**
   ```sh
   docker compose --env-file .env up -d
   ```
   Postgres comes from the public image, Phoenix from GHCR. `bin/migrate` runs automatically
   on start before the server. Traefik picks up the new container from its labels.

### Verify success

```sh
docker compose ps                                              # all services "healthy"
curl -fsS https://beta.buterland-beckerhook.de/health/liveness # 200 (once TLS is issued)
```
In the browser: `https://beta.buterland-beckerhook.de` → Basic-Auth dialog, then the home
page renders; the response carries the header `X-Robots-Tag: noindex, nofollow`.
Admin login at `/users/log-in`.

## Update flow ("practice")

1. Commit the change and push to `feat/phoenix-rewrite` → CI builds a fresh `:beta` image.
2. On the server, pull the new image and restart the container:
   ```sh
   docker compose --env-file .env pull phoenix
   docker compose --env-file .env up -d phoenix
   ```
   Migrations run automatically on restart. Short downtime is fine for Beta.

### Rollback

Every build is additionally tagged as an immutable `:sha-XXXXXXX` (short commit SHA, see the
Actions log or GHCR). To roll back to an earlier state:
```sh
# in .env:  IMAGE=ghcr.io/buterland-beckerhook/app:sha-abc1234
docker compose --env-file .env pull phoenix
docker compose --env-file .env up -d phoenix
```

## Prod (later)

Use the same stack for Prod with its own `.env`:
- `PHX_HOST=buterland-beckerhook.de`
- `TRAEFIK_NAME=bb`
- `TRAEFIK_RULE=Host(\`buterland-beckerhook.de\`, \`www.buterland-beckerhook.de\`)`
- `TRAEFIK_MIDDLEWARES=bb-compress,bb-www` (compression + www→apex redirect, **without** Basic-Auth/noindex)
- `BASIC_AUTH_USERS=` (empty)
- point `IMAGE` at a stable `:sha-XXXXXXX` tag.

Beta and Prod run on the same Traefik — so pick **different `TRAEFIK_NAME`s** (`bb-beta` vs. `bb`),
otherwise router/middleware names collide.

## Backups

`deploy/backup.sh` — nightly `pg_dump` + uploads, offsite via Borg (cron as root). The restore
runbook is at the top of the script.
