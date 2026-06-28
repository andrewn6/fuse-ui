# This file is responsible for configuring your application
# and its dependencies with the aid of the Config module.
#
# This configuration file is loaded before any dependency and
# is restricted to this project.

# General application configuration
import Config

config :fuse,
  ecto_repos: [Fuse.Repo],
  generators: [timestamp_type: :utc_datetime],
  # Baked at compile time so the app can detect prod at boot (Mix is unavailable
  # in releases). Used to warn when prod runs without an inbound API token.
  env: config_env()

# Fuse orchestrator REST client. The HTTP impl is the default; tests swap in
# Fuse.Client.Fake. base_url/token are typically set in config/runtime.exs.
config :fuse, :fuse_client, Fuse.Client.HTTP

config :fuse, Fuse.Client.HTTP, base_url: "http://localhost:8080"

# SSE event-stream source; the HTTP impl is the default, tests swap in the fake.
config :fuse, :event_source, Fuse.EventStream.Source.HTTP

# Inbound control-plane API auth (callers -> this app). Distinct from the outbound
# fuse token. nil = auth disabled (dev/test); set CONTROL_PLANE_TOKEN in runtime.exs.
config :fuse, FuseWeb.Plugs.ApiAuth, token: nil

# Browser-console auth gate (admin password + first-host onboarding). On by
# default so a deployed console is never open; disabled in config/test.exs and
# overridable via CONSOLE_AUTH_ENFORCE in runtime.exs.
config :fuse, FuseWeb.Auth, enforce: true

# Resource caps enforced before a create is forwarded to fuse. Generous defaults
# that won't reject normal plans; tune per deployment. A nil cap means "no limit".
config :fuse, Fuse.Bounds,
  max_cpus: 64,
  max_ram_mb: 262_144,
  max_storage_gb: 4_096,
  max_runtime_seconds: 604_800

# Write-endpoint rate limiting (fixed window per remote IP). Off by default
# (limit: nil) so dev/test are unthrottled; set a limit in runtime.exs for prod.
config :fuse, FuseWeb.Plugs.RateLimiter, limit: nil, window_ms: 60_000

# Source-network allowlist for the control-plane API. Empty = open to all
# sources; set CONTROL_PLANE_ALLOWED_CIDRS in runtime.exs to restrict.
config :fuse, FuseWeb.Plugs.CidrAllowlist, cidrs: []

# Local read-model mirror + audit log of mutating actions. Disabled in test (see
# config/test.exs) so the proxy hot path never touches the DB there; enabled
# elsewhere. Best-effort: a mirror/audit write failure never breaks a request.
config :fuse, Fuse.Mirror, enabled: true
config :fuse, Fuse.Audit, enabled: true

# Configures the endpoint
config :fuse, FuseWeb.Endpoint,
  url: [host: "localhost"],
  adapter: Bandit.PhoenixAdapter,
  render_errors: [
    formats: [html: FuseWeb.ErrorHTML, json: FuseWeb.ErrorJSON],
    layout: false
  ],
  pubsub_server: Fuse.PubSub,
  live_view: [signing_salt: "hVleE6ZC"]

# Configures the mailer
#
# By default it uses the "Local" adapter which stores the emails
# locally. You can see the emails in your browser, at "/dev/mailbox".
#
# For production it's recommended to configure a different adapter
# at the `config/runtime.exs`.
config :fuse, Fuse.Mailer, adapter: Swoosh.Adapters.Local

# Configure esbuild (the version is required)
config :esbuild,
  version: "0.25.4",
  fuse: [
    args:
      ~w(js/app.js --bundle --target=es2022 --outdir=../priv/static/assets/js --external:/fonts/* --external:/images/* --alias:@=.),
    cd: Path.expand("../assets", __DIR__),
    env: %{"NODE_PATH" => [Path.expand("../deps", __DIR__), Mix.Project.build_path()]}
  ]

# Configure tailwind (the version is required)
config :tailwind,
  version: "4.1.7",
  fuse: [
    args: ~w(
      --input=assets/css/app.css
      --output=priv/static/assets/css/app.css
    ),
    cd: Path.expand("..", __DIR__)
  ]

# Configures Elixir's Logger
config :logger, :default_formatter,
  format: "$time $metadata[$level] $message\n",
  metadata: [:request_id]

# Use Jason for JSON parsing in Phoenix
config :phoenix, :json_library, Jason

# Import environment specific config. This must remain at the bottom
# of this file so it overrides the configuration defined above.
import_config "#{config_env()}.exs"
