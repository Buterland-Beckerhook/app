defmodule BbhWeb.Router do
  use BbhWeb, :router

  import BbhWeb.UserAuth

  pipeline :browser do
    plug BbhWeb.Plugs.TrailingSlash
    plug :accepts, ["html"]
    plug :fetch_session
    plug :fetch_live_flash
    plug :put_root_layout, html: {BbhWeb.Layouts, :root}
    plug :protect_from_forgery
    plug :put_secure_browser_headers
    plug BbhWeb.Plugs.CSP
    plug :fetch_current_scope_for_user
    plug BbhWeb.Plugs.TrackPageView
  end

  pipeline :api do
    plug :accepts, ["json"]
  end

  # Session-backed JSON for fetch() calls from the site's own pages: carries the
  # session and CSRF protection of :browser (the caller sends the csrf-token meta
  # value as x-csrf-token) but negotiates JSON and renders no layout.
  pipeline :browser_json do
    plug :accepts, ["json"]
    plug :fetch_session
    plug :protect_from_forgery
    plug :put_secure_browser_headers
    plug :fetch_current_scope_for_user
  end

  # Only for the final catch-all below. Like :browser minus what a 404 does not need:
  # no page-view tracking and no `accepts` (a bot asking for JSON still gets a 404, not
  # a 406). No TrailingSlash either — BbhWeb.Redirector normalizes the path itself, so
  # an old "/foo/" URL is redirected in one hop. Session, scope, root layout and CSP
  # stay: the 404 page renders in the full site layout. protect_from_forgery is a no-op
  # for the GET-only route, but a session-fetching pipeline must carry it (Sobelow
  # Config.CSRF) and it keeps the layout's csrf meta tag backed by the session.
  pipeline :not_found do
    plug :fetch_session
    plug :fetch_live_flash
    plug :put_root_layout, html: {BbhWeb.Layouts, :root}
    plug :protect_from_forgery
    plug :put_secure_browser_headers
    plug BbhWeb.Plugs.CSP
    plug :fetch_current_scope_for_user
  end

  # iCalendar feeds, fetched by calendar clients rather than browsers. No `accepts`:
  # Apple Calendar (dataaccessd) validates a subscription with `Accept: text/calendar`,
  # which `accepts ["html"]` answers with 406, so the subscription fails. No session,
  # CSRF, layout or CSP either — a feed needs none of them. Page-view tracking stays:
  # it counts subscription-feed retrievals.
  pipeline :ical do
    plug :put_secure_browser_headers
    plug BbhWeb.Plugs.TrackPageView
  end

  # The MCP endpoint. Deliberately not `:browser`: it must not touch the session, the
  # CSRF token or the page-view tracker, and its only credential is a bearer token.
  pipeline :mcp do
    plug :accepts, ["json"]
    plug BbhWeb.Plugs.CORS
    plug BbhWeb.Plugs.ApiAuth
  end

  # The machine-facing half of the OAuth 2.1 authorization server (discovery, dynamic
  # registration, token). Unauthenticated by construction — see the controller — and CORS
  # is open for the same reason it is on /mcp: no cookie or session is read here.
  pipeline :oauth_api do
    plug :accepts, ["json"]
    plug BbhWeb.Plugs.CORS
  end

  scope "/", BbhWeb.Api do
    pipe_through :oauth_api

    # RFC 9728. Both spellings: the spec derives the second by inserting the resource's
    # path, and clients probe them in different orders.
    get "/.well-known/oauth-protected-resource", OAuthController, :protected_resource
    get "/.well-known/oauth-protected-resource/mcp", OAuthController, :protected_resource
    # RFC 8414.
    get "/.well-known/oauth-authorization-server", OAuthController, :authorization_server

    post "/oauth/register", OAuthController, :register
    post "/oauth/token", OAuthController, :token
  end

  # Admin-only: flag the current browser's push subscription as a test receiver.
  scope "/push", BbhWeb do
    # Authorization (admin) is checked in the controller, which answers 403 in JSON
    # instead of the login redirect :require_authenticated_user would send.
    pipe_through :browser_json

    post "/tester", PushTesterController, :update
  end

  # Consent. On the browser pipeline on purpose: the site's own login (magic link or
  # passkey, plus TOTP) is the OAuth login. See docs/adr/0010-mcp-oauth.md.
  scope "/oauth", BbhWeb do
    pipe_through [:browser, :require_authenticated_user]

    get "/authorize", OAuthController, :new
    post "/authorize", OAuthController, :create
  end

  # Model Context Protocol server — lets an assistant draft articles on the user's
  # behalf, with that user's own permissions. See docs/adr/0009-mcp-server.md.
  scope "/mcp", BbhWeb.Api do
    pipe_through :mcp

    post "/", MCPController, :create
    # The transport also defines GET (open an SSE stream) and DELETE (end the session) on
    # the endpoint; this server offers neither, and 405 is how it says so.
    get "/", MCPController, :no_stream
    delete "/", MCPController, :no_session
    # Preflight. The route only has to exist for the pipeline to run — BbhWeb.Plugs.CORS
    # halts with 204 before the controller is ever reached.
    options "/", MCPController, :no_session
  end

  scope "/api", BbhWeb.Api do
    pipe_through :api

    post "/push/subscribe", PushController, :subscribe
    post "/push/unsubscribe", PushController, :unsubscribe
    # POST, not GET: the endpoint is a secret URL and must not land in access logs.
    post "/push/status", PushController, :status

    # IBAN → BIC/Kreditinstitut for the membership form's live auto-fill.
    get "/blz", BlzController, :show
  end

  scope "/", BbhWeb do
    pipe_through :ical

    get "/termine/abo.ics", EventController, :feed
    # Legacy feed URL — keep so existing calendar subscriptions don't break.
    get "/termine/index.ics", EventController, :feed
    get "/termine/:year/:slug/event.ics", EventController, :ics

    # Revocable per-recipient share of one internal calendar (read-only .ics feed).
    get "/kalender/geteilt/:token", CalendarShareController, :feed
  end

  scope "/", BbhWeb do
    pipe_through :browser

    get "/", PageController, :home

    get "/aktuell", ArticleController, :index
    get "/aktuell/:year/:slug", ArticleController, :show

    get "/termine", EventController, :index
    get "/termine/:year/:slug", EventController, :show

    get "/thron", ThroneController, :index
    get "/thron/:type", ThroneController, :index_type

    # Registered before the "/verein/*path" catch-all so the membership form is not
    # swallowed by the dynamic page tree.
    get "/verein/mitglied-werden", MembershipController, :new
    post "/verein/mitglied-werden", MembershipController, :create

    get "/verein", PageContentController, :verein
    get "/verein/*path", PageContentController, :verein_page

    get "/impressum", PageContentController, :impressum
    get "/datenschutz", PageContentController, :datenschutz

    get "/suche", SearchController, :index

    get "/kontakt", ContactController, :new
    post "/kontakt", ContactController, :create

    get "/media/*path", MediaController, :show
    get "/sitemap.xml", SitemapController, :index
  end

  # Other scopes may use custom stacks.
  # scope "/api", BbhWeb do
  #   pipe_through :api
  # end

  # Enable LiveDashboard and Swoosh mailbox preview in development
  if Application.compile_env(:bbh, :dev_routes) do
    # If you want to use the LiveDashboard in production, you should put
    # it behind authentication and allow only admins to access it.
    # If your application does not have an admins-only section yet,
    # you can use Plug.BasicAuth to set up some basic authentication
    # as long as you are also using SSL (which you should anyway).
    import Phoenix.LiveDashboard.Router

    scope "/dev" do
      pipe_through :browser

      live_dashboard "/dashboard", metrics: BbhWeb.Telemetry
      forward "/mailbox", Plug.Swoosh.MailboxPreview
    end
  end

  ## Admin area (staff only)

  scope "/admin", BbhWeb.Admin do
    pipe_through [:browser, :require_authenticated_user]

    # Dashboard + Termine: open to any staff (admin, editor, calendar_editor).
    live_session :admin_staff, on_mount: [{BbhWeb.UserAuth, :require_staff}] do
      live "/", DashboardLive, :index

      live "/termine", EventLive.Index, :index
      live "/termine/teilen", ShareLive.Index, :index
      live "/termine/neu", EventLive.Form, :new
      live "/termine/:id/bearbeiten", EventLive.Form, :edit
    end

    # Content sections: admins and content editors only (not calendar editors).
    live_session :admin_content, on_mount: [{BbhWeb.UserAuth, :require_content_editor}] do
      live "/artikel", ArticleLive.Index, :index
      live "/artikel/neu", ArticleLive.Form, :new
      live "/artikel/:id/bearbeiten", ArticleLive.Form, :edit

      live "/orte", LocationLive.Index, :index
      live "/orte/neu", LocationLive.Form, :new
      live "/orte/:id/bearbeiten", LocationLive.Form, :edit

      live "/personen", PersonLive.Index, :index
      live "/personen/neu", PersonLive.Form, :new
      live "/personen/:id/bearbeiten", PersonLive.Form, :edit

      live "/medien", MediaLive.Index, :index

      live "/seiten", PageLive.Index, :index
      live "/seiten/neu", PageLive.Form, :new
      live "/seiten/:id/bearbeiten", PageLive.Form, :edit
    end

    # Admin-only sections.
    live_session :admin_only, on_mount: [{BbhWeb.UserAuth, :require_admin}] do
      live "/benutzer", UserLive.Index, :index
      live "/website", SiteSettingsLive, :index
      live "/push", PushLive, :index

      # Site-wide effect (a rule can send any old URL anywhere), hence admin-only.
      live "/weiterleitungen", RedirectLive.Index, :index
      live "/weiterleitungen/neu", RedirectLive.Form, :new
      live "/weiterleitungen/:id/bearbeiten", RedirectLive.Form, :edit
    end

    # Account settings — shown as a modal over the admin chrome. One live_session
    # so the sections (Account/Passkeys/2FA) patch in-place without a reload.
    live_session :admin_account, on_mount: [{BbhWeb.UserAuth, :require_staff}] do
      live "/einstellungen", SettingsLive, :account
      live "/einstellungen/passkeys", SettingsLive, :passkeys
      live "/einstellungen/2fa", SettingsLive, :totp
      live "/einstellungen/tokens", SettingsLive, :tokens
      live "/einstellungen/confirm-email/:token", SettingsLive, :confirm_email
    end
  end

  ## Authentication routes

  scope "/", BbhWeb do
    pipe_through [:browser, :require_authenticated_user]

    live_session :require_authenticated_user,
      on_mount: [{BbhWeb.UserAuth, :require_authenticated}] do
      live "/users/security", UserLive.SecuritySetup, :index
    end
  end

  scope "/", BbhWeb do
    pipe_through [:browser]

    # Invite-only: no public registration. Admins create accounts.
    live_session :current_user,
      on_mount: [{BbhWeb.UserAuth, :mount_current_scope}] do
      live "/users/log-in", UserLive.Login, :new
      live "/users/log-in/:token", UserLive.Confirmation, :new
    end

    post "/users/log-in", UserSessionController, :create
    delete "/users/log-out", UserSessionController, :delete
    delete "/users/log-out-all", UserSessionController, :delete_all

    # TOTP second-factor challenge (pending login held in the session).
    get "/users/totp", TotpController, :new
    post "/users/totp", TotpController, :create
  end

  ## Catch-all — MUST stay the last scope

  # Any GET no route above claimed. Before this existed such requests raised
  # NoRouteError; now they go through BbhWeb.Redirector, which serves editor-managed
  # redirects and old Hugo URLs, and logs real misses for /admin/weiterleitungen.
  scope "/", BbhWeb do
    pipe_through :not_found

    get "/*path", NotFoundController, :show
  end
end
