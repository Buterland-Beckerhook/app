defmodule BbhWeb.Router do
  use BbhWeb, :router

  pipeline :browser do
    plug :accepts, ["html"]
    plug :fetch_session
    plug :fetch_live_flash
    plug :put_root_layout, html: {BbhWeb.Layouts, :root}
    plug :protect_from_forgery
    plug :put_secure_browser_headers
  end

  pipeline :api do
    plug :accepts, ["json"]
  end

  scope "/", BbhWeb do
    pipe_through :browser

    get "/", PageController, :home

    get "/aktuell", ArticleController, :index
    get "/aktuell/:year/:slug", ArticleController, :show

    get "/termine", EventController, :index
    get "/termine/abo.ics", EventController, :feed
    get "/termine/:year/:slug", EventController, :show
    get "/termine/:year/:slug/event.ics", EventController, :ics

    get "/thron", ThroneController, :index

    get "/verein", PageContentController, :verein
    get "/verein/:slug", PageContentController, :verein_page

    get "/impressum", PageContentController, :impressum
    get "/datenschutz", PageContentController, :datenschutz

    get "/kontakt", ContactController, :new
    post "/kontakt", ContactController, :create
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
end
