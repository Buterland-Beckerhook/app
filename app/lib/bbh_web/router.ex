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

  scope "/api", BbhWeb.Api do
    pipe_through :api

    post "/push/subscribe", PushController, :subscribe
    post "/push/unsubscribe", PushController, :unsubscribe
  end

  scope "/", BbhWeb do
    pipe_through :browser

    get "/", PageController, :home

    get "/aktuell", ArticleController, :index
    get "/aktuell/:year/:slug", ArticleController, :show

    get "/termine", EventController, :index
    get "/termine/abo.ics", EventController, :feed
    # Legacy feed URL — keep so existing calendar subscriptions don't break.
    get "/termine/index.ics", EventController, :feed
    get "/termine/:year/:slug", EventController, :show
    get "/termine/:year/:slug/event.ics", EventController, :ics

    get "/thron", ThroneController, :index
    get "/thron/:type", ThroneController, :index_type

    get "/verein", PageContentController, :verein
    get "/verein/*path", PageContentController, :verein_page

    get "/impressum", PageContentController, :impressum
    get "/datenschutz", PageContentController, :datenschutz

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
    end

    # Account settings — shown as a modal over the admin chrome. One live_session
    # so the sections (Account/Passkeys/2FA) patch in-place without a reload.
    live_session :admin_account, on_mount: [{BbhWeb.UserAuth, :require_staff}] do
      live "/einstellungen", SettingsLive, :account
      live "/einstellungen/passkeys", SettingsLive, :passkeys
      live "/einstellungen/2fa", SettingsLive, :totp
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

    # TOTP second-factor challenge (pending login held in the session).
    get "/users/totp", TotpController, :new
    post "/users/totp", TotpController, :create
  end
end
