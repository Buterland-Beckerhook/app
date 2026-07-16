# Deployment Validation: buterland-beckerhook (Phoenix, Docker Compose + Caddy)

## Summary
Core release/runtime config follows `phx.gen.release` conventions correctly (runtime secrets, `mix release`, non-root Dockerfile user, migrate-then-serve command). However there are **no health-check endpoints at all**, no graceful-shutdown/drain configuration anywhere (Bandit default + Docker default = connections killed in ~10-15s), DB SSL is explicitly disabled, and `PHX_HOST` silently falls back to a bogus default instead of failing fast. These should be fixed before going live.

## Blockers (Must Fix)

### No health check endpoints
- **Location**: `app/lib/bbh_web/router.ex` (no `/health/*` routes), `app/lib/bbh_web/endpoint.ex` (no health plug before router), `deploy/compose.yml:29-49` (phoenix service has no `healthcheck:`), `app/Dockerfile` (no `HEALTHCHECK`)
- **Problem**: Neither liveness nor readiness (DB-checking) endpoints exist. Compose only health-checks `postgres`, not `phoenix`; Caddy `reverse_proxy` has no `health_uri`, so it will keep sending traffic to a booting/broken app instance.
- **Fix**: Add a lightweight health plug (startup/liveness always-200, readiness doing `SELECT 1` via `Ecto.Adapters.SQL.query`) mounted before the router, add `healthcheck:` to the `phoenix` service in compose, and add `health_uri`/`health_port` (or `lb_try_duration`) to the Caddy `reverse_proxy` block.

### No graceful shutdown configuration (< 60s effective)
- **Location**: `app/lib/bbh_web/endpoint.ex` (no `drainer`/shutdown_timeout config), `deploy/compose.yml:20-49` (no `stop_grace_period` on `phoenix`)
- **Problem**: Bandit's default shutdown timeout is well under 60s and Docker Compose's default `stop_grace_period` is 10s, after which SIGKILL is sent. In-flight requests and LiveView websocket connections will be dropped on every deploy/restart.
- **Fix**: Set `stop_grace_period: 60s` (or more) on the `phoenix` service, and configure an explicit `http: [..., shutdown_timeout: ...]`/drainer in the endpoint so Bandit drains connections rather than being killed abruptly.

### DB SSL disabled entirely (not just missing verify_peer)
- **Location**: `app/config/runtime.exs:52` — `# ssl: true,` is commented out in the `Bbh.Repo` config
- **Problem**: Iron Law 4 requires SSL with `verify: :verify_peer` for DB connections. Here SSL is off completely, no encryption between `phoenix` and `postgres` containers.
- **Fix**: Even on the internal compose network, enable `ssl: true, ssl_opts: [verify: :verify_peer, cacertfile: ...]` if the Postgres image/cert setup supports it; if intentionally skipped because traffic never leaves the Docker bridge network, document that explicitly as an accepted risk rather than leaving it silently commented out.

### `PHX_HOST` silently defaults instead of failing fast
- **Location**: `app/config/runtime.exs:74` — `host = System.get_env("PHX_HOST") || "example.com"`
- **Problem**: Unlike `DATABASE_URL`/`SECRET_KEY_BASE`, a missing `PHX_HOST` does not raise; the app will boot and serve with `url: [host: "example.com", ...]`, silently breaking URL generation, emails, sitemap, and `force_ssl`/CSRF-adjacent host checks — a hard-to-diagnose production misconfiguration.
- **Fix**: `System.get_env("PHX_HOST") || raise "PHX_HOST is required"`, matching the pattern already used for `DATABASE_URL`/`SECRET_KEY_BASE` and consistent with `.env.example` which requires it.

## Warnings

- **`deploy/Caddyfile:1-8`** — No explicit `tls` block (email for ACME notifications, or `on_demand`), and no security headers (HSTS is already set by Phoenix `force_ssl`, but consider adding `header` block for defense-in-depth e.g. `X-Content-Type-Options`). Not blocking since Phoenix's `put_secure_browser_headers` + `force_ssl` cover most of this for HTML routes, but `/api` and `/media` responses go through the same pipeline — verify.
- **`app/config/config.exs:9-15`** — `force_ssl` `exclude: [hosts: ["localhost", "127.0.0.1"]]` has no exclusion for future health endpoints; once health routes are added, add `paths: ["/health"]` so Docker/Caddy healthchecks (likely plain HTTP from inside the container) aren't redirected to HTTPS and fail.
- **`deploy/backup.sh:14`** — `pg_dump ... > file` combined with `set -e` is fine, but there's no verification step (e.g. `pg_restore --list` sanity check) before pruning older backups; a silently-corrupt dump could still cause the last 3 good copies to be rotated out. Consider verifying dump integrity before `xargs rm`.
- **`deploy/backup.sh:20`** — `docker run --rm -v bbh_uploads:/data ...` hardcodes the volume name `bbh_uploads`; this only matches if the compose project name is `bbh` (default is the directory name, which is `deploy` here unless `COMPOSE_PROJECT_NAME` is set) — verify this matches the actual volume name (`docker volume ls`) or the backup will silently back up an empty/nonexistent volume.
- **`deploy/compose.yml:10-19`** — `postgres` has no `POOL_SIZE`-aware tuning info (no `shared_buffers`/`max_connections` tuning); default Postgres `max_connections=100` vs Phoenix `pool_size=10` is fine for one instance, but if `phoenix` is ever scaled to multiple replicas this will need coordination. Also no volume/permission hardening (`POSTGRES_INITDB_ARGS` etc.) — low priority for a single-tenant club site.
- **`deploy/.env.example`** — Does not document `POOL_SIZE`, `ECTO_IPV6`, or `DNS_CLUSTER_QUERY`, which `runtime.exs` reads (defaults are sane, so not a blocker, but worth documenting for operators tuning the DB pool).
- **`app/config/config.exs:5-6`** — Structured (JSON) logging is not configured; default text formatter is used (`config :logger, :default_formatter, format: "$time $metadata[$level] $message\n"`). Fine for `docker compose logs`, but if logs are ever shipped to a log aggregator, JSON would be easier to parse. No error-tracking service (Sentry/AppSignal) integration found anywhere in `mix.exs`/`lib`.
- **`app/Dockerfile`** — Standard `phx.gen.release` multi-stage build; runner installs `libstdc++6 openssl libncurses6 locales ca-certificates`, no unpinned `apt-get upgrade`, non-root `nobody` user — good. Only nit: no `HEALTHCHECK` directive (ties to blocker above) and no `tini`/init process for zombie reaping — acceptable for a single-process BEAM release under Compose's own PID 1 handling, but note the commented-out `ENTRYPOINT ["/tini", "--"]` suggestion in the file itself.

## Configuration Review

### Runtime Configuration
- Status: ⚠️
- Secrets in runtime.exs: yes (`DATABASE_URL`, `SECRET_KEY_BASE`, SMTP, VAPID, ALTCHA all read at runtime via `System.get_env`)
- Required env vars validated: partially — `DATABASE_URL` and `SECRET_KEY_BASE` raise if missing; `PHX_HOST` does not (blocker above)
- Pool size configurable: yes, `POOL_SIZE` env var, default `10`

### Health Checks
- Status: ❌
- Startup: none
- Liveness: none
- Readiness: none

### Container Configuration
- Status: ⚠️
- Non-root user: yes (`nobody`, chowned `/app`)
- CPU limits: none set in `compose.yml` — correct (no violation)
- Grace period: not set (Docker default ~10s) — should be ≥60s

### Database
- Status: ❌
- SSL enabled: no (commented out)
- SSL verification: no
- Pool size: configurable via `POOL_SIZE`, default 10

### Observability
- Status: ⚠️
- Structured logging: no (plain text formatter)
- Error tracking: none configured
- Metrics: `BbhWeb.Telemetry` present (default Phoenix telemetry supervisor), no external exporter (Prometheus/AppSignal) found

## Pre-Deploy Checklist
- [ ] Add `/health/startup`, `/health/liveness`, `/health/readiness` endpoints and wire into Caddy + compose healthcheck
- [ ] Set `stop_grace_period: 60s` on `phoenix` service and configure Bandit/endpoint drain timeout
- [ ] Decide on and implement DB SSL (or explicitly document why it's skipped on the internal network)
- [ ] Make `PHX_HOST` raise when missing instead of defaulting to `example.com`
- [ ] Verify `bbh_uploads` volume name in `backup.sh` matches actual compose project volume name
- [ ] Migrations tested (none inspected in this pass — recommend a follow-up migration-safety review of `priv/repo/migrations/`)
- [ ] Rollback procedure documented (backup.sh restore runbook exists — verify it's been tested end-to-end)
- [ ] Monitoring dashboards / alerts for Caddy + Phoenix + Postgres containers
