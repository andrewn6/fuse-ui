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
