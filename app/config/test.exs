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

# Disable rate limiting in tests so it doesn't interfere
config :bbh, BbhWeb.RateLimit, enabled: false

# Disable async page-view tracking in tests (the spawned writes escape the
# SQL sandbox); analytics behaviour is covered directly in Bbh.AnalyticsTest.
config :bbh, BbhWeb.Plugs.TrackPageView, enabled: false

# In test we don't send emails
config :bbh, Bbh.Mailer, adapter: Swoosh.Adapters.Test

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
