import Config

# config/runtime.exs is executed for all environments, including
# during releases. It is executed after compilation and before the
# system starts, so it is typically used to load production configuration
# and secrets from environment variables or elsewhere. Do not define
# any compile-time configuration in here, as it won't be applied.
# The block below contains prod specific runtime configuration.

# ## Using releases
#
# If you use `mix release`, you need to explicitly enable the server
# by passing the PHX_SERVER=true when you start it:
#
#     PHX_SERVER=true bin/bbh start
#
# Alternatively, you can use `mix phx.gen.release` to generate a `bin/server`
# script that automatically sets the env var above.
if System.get_env("PHX_SERVER") do
  config :bbh, BbhWeb.Endpoint, server: true
end

config :bbh, BbhWeb.Endpoint, http: [port: String.to_integer(System.get_env("PORT", "4000"))]

# Time zone the club operates in (iCal TZID). Env-overridable in every environment
# so releases can set it without a rebuild; defaults to Europe/Berlin.
if tz = System.get_env("TIME_ZONE") do
  config :bbh, :time_zone, tz
end

# Postfach (ticket system). Off until the switch-over (on in dev, see dev.exs); the old
# mail path stays meanwhile. Only an explicitly set variable overrides the default.
if enabled = System.get_env("TICKETS_ENABLED") do
  config :bbh, :tickets_enabled, enabled in ~w(true 1)
end

# Per-queue addresses (Bbh.Tickets.Queue), e.g. test aliases on Beta:
# "info=info-beta@…,vorstand=vorstand-beta@…". Unlisted queues keep the club address.
if addresses = System.get_env("TICKET_QUEUE_ADDRESSES") do
  config :bbh, :ticket_queue_addresses, addresses
end

# Field encryption keys for the Postfach (Bbh.Vault). Set together; Beta gets its own,
# never Prod's. Checked at boot when TICKETS_ENABLED is on.
if keys = System.get_env("TICKET_KEYS") do
  config :bbh, Bbh.Vault,
    keys: keys,
    current_key: System.get_env("TICKET_KEY_CURRENT"),
    hmac_key: System.get_env("TICKET_HMAC_KEY")
end

# Login log retention (Bbh.Accounts.AuthLog), stated in the Datenschutzerklärung.
if days = System.get_env("AUTH_LOG_RETENTION_DAYS") do
  config :bbh, :auth_log_retention_days, String.to_integer(days)
end

# The public beta: never indexed, banner on every page linking the live site (BbhWeb.Beta).
# `BETA=true` turns it on (`BETA_NOINDEX` is its former name); a `beta.` host turns it on
# by itself, so a forgotten variable cannot expose the beta. Independent of the
# reverse-proxy `noindex` middleware. Leave unset in prod.
config :bbh,
       :beta,
       String.starts_with?(System.get_env("PHX_HOST", ""), "beta.") or
         Enum.any?(~w(BETA BETA_NOINDEX), &(System.get_env(&1) in ~w(true 1)))

config :bbh, :live_url, System.get_env("LIVE_URL", "https://buterland-beckerhook.de")

if config_env() == :dev do
  # Reload browser tabs when matching files change.
  config :bbh, BbhWeb.Endpoint,
    live_reload: [
      web_console_logger: true,
      patterns: [
        # Static assets, except user uploads
        ~r"priv/static/(?!uploads/).*\.(js|css|png|jpeg|jpg|gif|svg)$"E,
        # Gettext translations
        ~r"priv/gettext/.*\.po$"E,
        # Router, Controllers, LiveViews and LiveComponents
        ~r"lib/bbh_web/router\.ex$"E,
        ~r"lib/bbh_web/(controllers|live|components)/.*\.(ex|heex)$"E
      ]
    ]
end

if config_env() == :prod do
  database_url =
    System.get_env("DATABASE_URL") ||
      raise """
      environment variable DATABASE_URL is missing.
      For example: ecto://USER:PASS@HOST/DATABASE
      """

  maybe_ipv6 = if System.get_env("ECTO_IPV6") in ~w(true 1), do: [:inet6], else: []

  config :bbh, Bbh.Repo,
    # DB SSL is intentionally OFF: Postgres is only reachable over the internal
    # Docker Compose network (not exposed publicly), so TLS to the DB adds no
    # meaningful protection here. Accepted risk — enable `ssl: true` if the DB
    # is ever moved to a shared/remote host.
    url: database_url,
    pool_size: String.to_integer(System.get_env("POOL_SIZE") || "10"),
    # For machines with several cores, consider starting multiple pools of `pool_size`
    # pool_count: 4,
    socket_options: maybe_ipv6

  # The secret key base is used to sign/encrypt cookies and other secrets.
  # A default value is used in config/dev.exs and config/test.exs but you
  # want to use a different value for prod and you most likely don't want
  # to check this value into version control, so we use an environment
  # variable instead.
  secret_key_base =
    System.get_env("SECRET_KEY_BASE") ||
      raise """
      environment variable SECRET_KEY_BASE is missing.
      You can generate one by calling: mix phx.gen.secret
      """

  host =
    System.get_env("PHX_HOST") ||
      raise "environment variable PHX_HOST is required (e.g. buterland-beckerhook.de)"

  config :bbh, :dns_cluster_query, System.get_env("DNS_CLUSTER_QUERY")

  # Log verbosity is env-tunable (LOG_LEVEL) so prod can be dialed up to :debug
  # temporarily — e.g. to see the /health probe lines the endpoint keeps at
  # :debug — without rebuilding the image. Defaults to :info; an unknown value
  # fails the boot loudly rather than silently logging at the wrong level.
  log_level =
    case System.get_env("LOG_LEVEL", "info") do
      level when level in ~w(emergency alert critical error warning notice info debug) ->
        String.to_existing_atom(level)

      other ->
        raise """
        invalid LOG_LEVEL #{inspect(other)}.
        Expected one of: debug info notice warning error critical alert emergency
        """
    end

  config :logger, level: log_level

  config :bbh, BbhWeb.Endpoint,
    url: [host: host, port: 443, scheme: "https"],
    http: [
      # Enable IPv6 and bind on all interfaces.
      # Set it to  {0, 0, 0, 0, 0, 0, 0, 1} for local network only access.
      # See the documentation on https://bandit.hexdocs.pm/Bandit.html#t:options/0
      # for details about using IPv6 vs IPv4 and loopback vs public addresses.
      ip: {0, 0, 0, 0, 0, 0, 0, 0},
      # Bandit drains connections on shutdown; give in-flight requests up to
      # 55s to finish (kept under the container's 60s stop_grace_period).
      thousand_island_options: [shutdown_timeout: 55_000]
    ],
    secret_key_base: secret_key_base

  # ## SSL Support
  #
  # To get SSL working, you will need to add the `https` key
  # to your endpoint configuration:
  #
  #     config :bbh, BbhWeb.Endpoint,
  #       https: [
  #         ...,
  #         port: 443,
  #         cipher_suite: :strong,
  #         keyfile: System.get_env("SOME_APP_SSL_KEY_PATH"),
  #         certfile: System.get_env("SOME_APP_SSL_CERT_PATH")
  #       ]
  #
  # The `cipher_suite` is set to `:strong` to support only the
  # latest and more secure SSL ciphers. This means old browsers
  # and clients may not be supported. You can set it to
  # `:compatible` for wider support.
  #
  # `:keyfile` and `:certfile` expect an absolute path to the key
  # and cert in disk or a relative path inside priv, for example
  # "priv/ssl/server.key". For all supported SSL configuration
  # options, see https://plug.hexdocs.pm/Plug.SSL.html#configure/1
  #
  # We also recommend setting `force_ssl` in your config/prod.exs,
  # ensuring no data is ever sent via http, always redirecting to https:
  #
  #     config :bbh, BbhWeb.Endpoint,
  #       force_ssl: [hsts: true]
  #
  # Check `Plug.SSL` for all available options in `force_ssl`.

  # Media storage (mounted volume) + site settings.
  config :bbh,
    uploads_dir: System.get_env("UPLOADS_DIR") || "/data/uploads",
    media_cache_dir: System.get_env("MEDIA_CACHE_DIR") || "/data/uploads_cache",
    site_url: "https://#{host}",
    contact_recipient: System.get_env("CONTACT_RECIPIENT") || "info@buterland-beckerhook.de",
    contact_sender: System.get_env("CONTACT_SENDER") || "noreply@buterland-beckerhook.de",
    contact_sender_name: System.get_env("CONTACT_SENDER_NAME") || "Buterland-Beckerhook.de",
    altcha_hmac_key: System.get_env("ALTCHA_HMAC_KEY"),
    membership_min_age: String.to_integer(System.get_env("MEMBERSHIP_MIN_AGE") || "16"),
    membership_max_child_age:
      String.to_integer(System.get_env("MEMBERSHIP_MAX_CHILD_AGE") || "15")

  # Map archive inside the uploads volume (excluded from backups: regenerable).
  config :bbh, Bbh.Map, dir: System.get_env("MAP_DIR") || "/data/map"

  # Uploaded BLZ table inside the data volume (see Bbh.Blz).
  config :bbh, Bbh.Blz, upload_file: System.get_env("BLZ_DATA_FILE") || "/data/blz.tsv"

  # Contact form email via the club's own SMTP server.
  smtp_relay = System.get_env("SMTP_RELAY")

  smtp = [
    adapter: Swoosh.Adapters.SMTP,
    relay: smtp_relay,
    port: String.to_integer(System.get_env("SMTP_PORT") || "587"),
    tls: :always,
    auth: :always,
    # Submission relay: connect straight to SMTP_RELAY, don't chase its MX records
    # (keeps the connected host aligned with the SNI/cert name below).
    no_mx_lookups: true,
    # gen_smtp's default tls_options set only `versions` (no `verify`/`cacerts`).
    # Since OTP 26 `ssl:connect` defaults `verify` to `:verify_peer`, so those
    # defaults are rejected as {:options, :incompatible, [verify: :verify_peer,
    # cacerts: :undefined]} *before* the handshake — gen_smtp then sends a
    # plaintext QUIT on the STARTTLS-primed socket, which the relay reports as an
    # SSL "wrong version number" and we see as {:temporary_failure, :tls_failed}.
    # Supply a self-consistent verifying config so the STARTTLS upgrade proceeds.
    tls_options: [
      versions: [:"tlsv1.2", :"tlsv1.3"],
      verify: :verify_peer,
      cacerts: :public_key.cacerts_get(),
      server_name_indication: String.to_charlist(smtp_relay || ""),
      depth: 3,
      customize_hostname_check: [
        match_fun: :public_key.pkix_verify_hostname_match_fun(:https)
      ]
    ]
  ]

  config :bbh,
         Bbh.Mailer,
         smtp ++
           [username: System.get_env("SMTP_USERNAME"), password: System.get_env("SMTP_PASSWORD")]

  # Postfach replies through the tickets@ mailbox (Bbh.TicketMailer) — only when its
  # credentials are set; no fallback to the noreply@ account. Beta uses its own mailbox.
  if ticket_smtp_user = System.get_env("TICKET_SMTP_USERNAME") do
    config :bbh,
           Bbh.TicketMailer,
           smtp ++ [username: ticket_smtp_user, password: System.get_env("TICKET_SMTP_PASSWORD")]
  else
    config :bbh, Bbh.TicketMailer, adapter: nil
  end

  config :swoosh, :api_client, false

  # Web Push (VAPID).
  config :web_push_elixir,
    vapid_public_key: System.get_env("VAPID_PUBLIC_KEY"),
    vapid_private_key: System.get_env("VAPID_PRIVATE_KEY"),
    vapid_subject: System.get_env("VAPID_SUBJECT") || "mailto:admin@buterland-beckerhook.de"
end
