import Config

# Configure your database
#
# The MIX_TEST_PARTITION environment variable can be used
# to provide built-in test partitioning in CI environment.
# Run `mix help test` for more information.
config :bbh, Bbh.Repo,
  username: "postgres",
  password: "postgres",
  # "localhost" for bare-metal; the compose dev stack sets DB_HOST=postgres.
  hostname: System.get_env("DB_HOST", "localhost"),
  database: "bbh_test#{System.get_env("MIX_TEST_PARTITION")}",
  pool: Ecto.Adapters.SQL.Sandbox,
  pool_size: System.schedulers_online() * 2

# We don't run a server during test. If one is required,
# you can enable the server option below.
config :bbh, BbhWeb.Endpoint,
  http: [ip: {127, 0, 0, 1}, port: 4002],
  secret_key_base: "d5tc7Dn6tuztJq1qgdkbyfwRKOTTPN3fmPplqz9jPd8VW4AzEY8kBn8HaWxrsjU7",
  server: false

# The endpoint's URL: host from config.exs, port from runtime.exs (PORT, default 4000,
# which wins over the http port above). Bbh.SiteTest keeps the two in step.
config :bbh, Bbh.Site, url: "http://localhost:4000"

# Disable rate limiting in tests so it doesn't interfere
config :bbh, BbhWeb.RateLimit, enabled: false

# No map downloads in tests: no boot fetch, no enqueue on location save. Worker
# tests turn it on with a stubbed HTTP client and a fake `pmtiles`.
config :bbh, Bbh.Map, auto_update: false, req_options: [plug: {Req.Test, Bbh.Map}]

# Uploaded BLZ table in a scratch path, so tests never see a dev upload. Tiny
# fixtures pass the "is this the real file" check.
config :bbh, Bbh.Blz,
  upload_file: Path.expand("../tmp/test/blz.tsv", __DIR__),
  min_entries: 2

# Run Oban jobs manually in tests (no queues/cron polling); use Oban.Testing.
config :bbh, Oban, testing: :manual

# Run push-notification side effects inline in tests: a detached task would
# borrow and outlive the SQL sandbox connection, flaking other async tests.
config :bbh, Bbh.Notifications, async: false

# No page-view tracking: its detached task would outlive the SQL sandbox of async
# tests. track_page_view_test turns it on (inline) for its own module.
config :bbh, BbhWeb.Plugs.TrackPageView, enabled: false

# Redirects: no node-global rule cache (async tests use separate sandboxes), and the
# 404 log is written inline so it stays inside the test's SQL sandbox.
config :bbh, Bbh.Redirects, cache: false
config :bbh, Bbh.Tickets.Queue, cache: false
config :bbh, Bbh.Calendar.Feeds, cache: false
config :bbh, BbhWeb.Redirector, async: false

# Don't pre-warm image variants in tests: the detached task would outlive the
# per-test temp dirs and log spurious mkdir failures during teardown.
config :bbh, :media_prewarm, false

# In test we don't send emails
config :bbh, Bbh.Mailer, adapter: Swoosh.Adapters.Test
config :bbh, Bbh.Tickets.Mailer, adapter: Swoosh.Adapters.Test

# Disable swoosh api client as it is only required for production adapters
config :swoosh, :api_client, false

# Print only warnings and errors during test
config :logger, level: :warning

# Initialize plugs at runtime for faster test compilation
config :phoenix, :plug_init_mode, :runtime

# Enable helpful, but potentially expensive runtime checks
config :phoenix_live_view,
  enable_expensive_runtime_checks: true

# Sort query params output of verified routes for robust url comparisons
config :phoenix,
  sort_verified_routes_query_params: true

# Postfach field encryption (Bbh.Vault): two keys, so rotation is testable.
config :bbh, Bbh.Vault,
  keys:
    "1:u9RC15scmJMvWayszFhjPQtglQTWmHeO3aOnZh4UDv4=,2:OY9GKth7niWJ7Ypg+qyWEqoFown+XJyH7s8F7HgXimk=",
  current_key: "2",
  hmac_key: "eF+UYuKVOgBT1mZ1kuZOLXWU93HHaKFg8pGumAve2aY="
