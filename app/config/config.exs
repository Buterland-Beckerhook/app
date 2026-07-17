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

# Time-zone database used by DateTime/2 conversions (provided by the :tz package).
config :elixir, :time_zone_database, Tz.TimeZoneDatabase

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
  bbh: [
    args:
      ~w(js/app.js --bundle --target=es2022 --outdir=../priv/static/assets/js --external:/fonts/* --external:/images/* --alias:@=.),
    cd: Path.expand("../assets", __DIR__),
    env: %{"NODE_PATH" => [Path.expand("../deps", __DIR__), Mix.Project.build_path()]}
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

# Import environment specific config. This must remain at the bottom
# of this file so it overrides the configuration defined above.
import_config "#{config_env()}.exs"
