# This file is responsible for configuring your application
# and its dependencies with the aid of the Config module.
#
# This configuration file is loaded before any dependency and
# is restricted to this project.

# General application configuration
import Config

config :bbh, :scopes,
  user: [
    default: true,
    module: Bbh.Accounts.Scope,
    assign_key: :current_scope,
    access_path: [:user, :id],
    schema_key: :user_id,
    schema_type: :binary_id,
    schema_table: :users,
    test_data_fixture: Bbh.AccountsFixtures,
    test_setup_helper: :register_and_log_in_user
  ]

config :bbh,
  ecto_repos: [Bbh.Repo],
  generators: [timestamp_type: :utc_datetime, binary_id: true]

# German-language site
config :gettext, :default_locale, "de"

# IANA time zone the club operates in. Drives "now" for event/article wall-clock
# times (Bbh.Time) and the iCal TZID. Overridable at runtime via the TIME_ZONE env
# var (see runtime.exs). The bundled VTIMEZONE encodes Central European (CET/CEST)
# DST rules, so a non-CET zone also needs matching transition rules in Bbh.ICal.
config :bbh, :time_zone, "Europe/Berlin"

# Contact published in /.well-known/security.txt (RFC 9116).
config :bbh, :security_contact, "webmaster@buterland-beckerhook.de"

# Membership-application age thresholds (per the Satzung). These are *soft*: the
# form only shows a hint and the club e-mail flags an out-of-range entry — nothing
# is rejected. Overridable at runtime via MEMBERSHIP_MIN_AGE / MEMBERSHIP_MAX_CHILD_AGE.
config :bbh, :membership_min_age, 16
config :bbh, :membership_max_child_age, 15

# Time-zone database used by DateTime/2 conversions (provided by the :tz package).
config :elixir, :time_zone_database, Tz.TimeZoneDatabase

# Fetch the precompiled MDEx NIF from the project's Cloudflare mirror instead of
# GitHub releases. GitHub's redirect to its asset host carries a ~9 KB CSP header,
# which pushes the response past :httpc's 10 KB header limit (`header_too_long`), so
# a clean deps.compile fails. The checksum is still verified against the package.
config :mdex_native, artifact_source: :cloudflare

# Media: original uploads live in :uploads_dir; derived responsive variants are
# cached (regenerable) in :media_cache_dir. Overridden per-env in runtime.exs.
config :bbh, :uploads_dir, Path.expand("../priv/uploads", __DIR__)
config :bbh, :media_cache_dir, Path.expand("../priv/uploads_cache", __DIR__)

# Configure the endpoint
config :bbh, BbhWeb.Endpoint,
  url: [host: "localhost"],
  adapter: Bandit.PhoenixAdapter,
  render_errors: [
    formats: [html: BbhWeb.ErrorHTML, json: BbhWeb.ErrorJSON],
    layout: false
  ],
  pubsub_server: Bbh.PubSub,
  live_view: [signing_salt: "b0Lmcjon"]

# Configure LiveView
config :phoenix_live_view,
  # the attribute set on all root tags. Used for Phoenix.LiveView.ColocatedCSS.
  root_tag_attribute: "phx-r"

# Configure the mailer
#
# By default it uses the "Local" adapter which stores the emails
# locally. You can see the emails in your browser, at "/dev/mailbox".
#
# For production it's recommended to configure a different adapter
# at the `config/runtime.exs`.
config :bbh, Bbh.Mailer, adapter: Swoosh.Adapters.Local

# Configure esbuild (the version is required)
config :esbuild,
  version: "0.25.4",
  # app.js plus the bundles it loads on demand (js/lazy/*: Quill, flatpickr, Altcha),
  # each built as its own IIFE next to it — assets/js/lazy/<name>.js. Listed one by one
  # (no glob): a new lazy bundle also needs its <meta name="bbh-lazy-…"> in the root
  # layout, so adding it here is a deliberate step.
  bbh: [
    args:
      ~w(js/app.js js/lazy/editor.js js/lazy/datepicker.js js/lazy/altcha.js --bundle --target=es2022 --outdir=../priv/static/assets/js --external:/fonts/* --external:/images/* --alias:@=.),
    cd: Path.expand("../assets", __DIR__),
    env: %{"NODE_PATH" => [Path.expand("../deps", __DIR__), Mix.Project.build_path()]}
  ],
  # The event map (MapLibre + PMTiles, ~1.5 MB) in its own bundle, loaded only by
  # pages that show a map. ESM, because MapLibre starts its worker as a module from
  # the second entry point (maplibre-gl-worker.js next to map.js).
  bbh_map: [
    args:
      ~w(js/map.js vendor/map/maplibre-gl-worker.mjs --bundle --format=esm --target=es2022 --outdir=../priv/static/assets/map --entry-names=[name] --alias:fflate=./vendor/map/fflate.mjs),
    cd: Path.expand("../assets", __DIR__)
  ]

# Configure tailwind (the version is required)
config :tailwind,
  version: "4.3.0",
  bbh: [
    args: ~w(
      --input=assets/css/app.css
      --output=priv/static/assets/css/app.css
    ),
    cd: Path.expand("..", __DIR__),
    env: %{"NODE_PATH" => [Path.expand("../deps", __DIR__), Mix.Project.build_path()]}
  ]

# Configure Elixir's Logger
config :logger, :default_formatter,
  format: "$time $metadata[$level] $message\n",
  metadata: [:request_id]

# Use Jason for JSON parsing in Phoenix
config :phoenix, :json_library, Jason

# Rate limiting (Hammer, ETS backend). Disabled in test.exs.
config :bbh, BbhWeb.RateLimit, enabled: true

# Content-Security-Policy. Disabled in dev.exs so LiveReload keeps working.
config :bbh, BbhWeb.Plugs.CSP, enabled: true

# Self-hosted event map (Bbh.Map, ADR 0014). The archive is extracted from the
# Protomaps daily build into :dir by Bbh.Workers.MapTilesUpdater, which needs the
# `pmtiles` CLI (in both Docker images). Protomaps builds stop at zoom 15; MapLibre
# overzooms beyond. Overridden per-env (runtime.exs, test.exs).
config :bbh, Bbh.Map,
  dir: Path.expand("../priv/tiles", __DIR__),
  auto_update: true,
  maxzoom: 15,
  build_base_url: "https://build.protomaps.com",
  pmtiles: "pmtiles"

# Background jobs (Oban). The cron plugin runs the publish notifier every five
# minutes so scheduled ("vorveröffentlichte") articles get their push once their
# publish date passes. Overridden to `testing: :manual` in test.exs.
config :bbh, Oban,
  repo: Bbh.Repo,
  queues: [default: 10, notifications: 5],
  plugins: [
    {Oban.Plugins.Pruner, max_age: 60 * 60 * 24 * 7},
    {Oban.Plugins.Cron,
     crontab: [
       {"*/5 * * * *", Bbh.Workers.ArticlePublishNotifier},
       {"*/5 * * * *", Bbh.Workers.EventPublishNotifier},
       {"*/5 * * * *", Bbh.Workers.EventReminderNotifier},
       # Rebuild the full-text search index; self-healing, so a coarse cadence is fine.
       {"*/15 * * * *", Bbh.Workers.SearchReindexer},
       # Reclaim dead MCP tokens and spent OAuth codes. Nightly is plenty — neither still
       # works by then, this only deletes the rows.
       {"30 3 * * *", Bbh.Workers.AuthPruner},
       # Forget 404-log entries nobody has hit for 90 days.
       {"45 3 * * *", Bbh.Workers.NotFoundPruner},
       # Fold visitor hashes older than seven days into daily totals and delete them.
       {"50 3 * * *", Bbh.Workers.AnalyticsRollup},
       # Refresh the map archive monthly — OSM edits are slow to matter here.
       {"17 4 3 * *", Bbh.Workers.MapTilesUpdater}
     ]}
  ]

# Import environment specific config. This must remain at the bottom
# of this file so it overrides the configuration defined above.
import_config "#{config_env()}.exs"
