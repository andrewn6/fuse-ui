defmodule FuseWeb.Router do
  use FuseWeb, :router

  pipeline :browser do
    plug :accepts, ["html"]
    plug :fetch_session
    plug :fetch_live_flash
    plug :put_root_layout, html: {FuseWeb.Layouts, :root}
    plug :protect_from_forgery
    plug :put_secure_browser_headers
    # Funnel every browser request to first-run setup until an admin password
    # exists (no-op once configured, or when enforcement is off).
    plug FuseWeb.Plugs.RequireSetup
  end

  pipeline :api do
    plug :accepts, ["json"]
    plug FuseWeb.Plugs.AuditActor
  end

  # Unauthenticated health probes for orchestrators. No auth/CIDR/rate-limit.
  pipeline :health do
    plug :accepts, ["json"]
  end

  # Inbound safety for the control-plane API, mirroring fuse's access-control
  # model. Ordered cheapest-gate-first: reject disallowed source networks, then
  # authenticate the bearer token, then rate-limit authenticated writes. Each
  # plug is a no-op until configured, so this layer is opt-in per deployment.
  pipeline :api_protected do
    plug FuseWeb.Plugs.CidrAllowlist
    plug FuseWeb.Plugs.ApiAuth
    plug FuseWeb.Plugs.RateLimiter
  end

  scope "/", FuseWeb do
    pipe_through :browser

    get "/", PageController, :home

    # First-run setup: create the admin password (only reachable until one exists).
    get "/setup", SetupController, :new
    post "/setup", SetupController, :create

    # Browser session login (admin password -> Phoenix session).
    get "/login", SessionController, :new
    post "/login", SessionController, :create
    delete "/logout", SessionController, :delete

    # The console. AuthHook gates it behind setup + login; HostGate keeps the
    # full console out of reach until a host is connected, funnelling to
    # /onboarding when the fleet is empty.
    live_session :console,
      on_mount: [FuseWeb.AuthHook, FuseWeb.HostGate, FuseWeb.CommandPalette, FuseWeb.Connection] do
      live "/onboarding", OnboardingLive, :index
      live "/environments", EnvironmentLive.Index, :index
      live "/environments/:id", EnvironmentLive.Show, :show
      live "/hosts", HostLive.Index, :index
      live "/snapshots", SnapshotLive.Index, :index
      live "/activity", ActivityLive.Index, :index
      live "/settings", SettingsLive.Index, :index
    end
  end

  scope "/", FuseWeb do
    pipe_through :health

    get "/healthz", HealthController, :live
    get "/readyz", HealthController, :ready
  end

  scope "/api/v1", FuseWeb.API do
    pipe_through [:api, :api_protected]

    get "/environments", EnvironmentController, :index
    post "/environments", EnvironmentController, :create
    get "/environments/:id", EnvironmentController, :show
    post "/environments/:id", EnvironmentController, :update
    delete "/environments/:id", EnvironmentController, :destroy

    post "/environments/:vm_id/snapshots", SnapshotController, :create
    get "/snapshots", SnapshotController, :index
    get "/snapshots/:id", SnapshotController, :show
    post "/snapshots/:id", SnapshotController, :update
    delete "/snapshots/:id", SnapshotController, :destroy

    get "/hosts", HostController, :index
    post "/hosts", HostController, :create
    get "/hosts/:id", HostController, :show
    post "/hosts/:id", HostController, :update
    delete "/hosts/:id", HostController, :destroy
  end

  # Enable LiveDashboard and Swoosh mailbox preview in development
  if Application.compile_env(:fuse, :dev_routes) do
    # If you want to use the LiveDashboard in production, you should put
    # it behind authentication and allow only admins to access it.
    # If your application does not have an admins-only section yet,
    # you can use Plug.BasicAuth to set up some basic authentication
    # as long as you are also using SSL (which you should anyway).
    import Phoenix.LiveDashboard.Router

    scope "/dev" do
      pipe_through :browser

      live_dashboard "/dashboard", metrics: FuseWeb.Telemetry
      forward "/mailbox", Plug.Swoosh.MailboxPreview
    end
  end
end
