import Config

# Configure your database
#
# The MIX_TEST_PARTITION environment variable can be used
# to provide built-in test partitioning in CI environment.
# Run `mix help test` for more information.
config :fuse, Fuse.Repo,
  database: Path.expand("../fuse_test.db", __DIR__),
  pool_size: 5,
  pool: Ecto.Adapters.SQL.Sandbox

# We don't run a server during test. If one is required,
# you can enable the server option below.
config :fuse, FuseWeb.Endpoint,
  http: [ip: {127, 0, 0, 1}, port: 4002],
  secret_key_base: "My3VzJPo9Gu2lOyQya0e/dKe5YOTKVl3Qgx5jEKT1k0ERWghTLu2sNv/ictboDC9",
  server: false

# In test we don't send emails
config :fuse, Fuse.Mailer, adapter: Swoosh.Adapters.Test

# Use the in-memory fake fuse client by default; HTTP client tests override the
# Fuse.Client.HTTP block per-test with a Req plug stub. retry: false keeps
# error-path tests from triggering Req's transient-failure retries.
config :fuse, :fuse_client, Fuse.Client.Fake

config :fuse, Fuse.Client.HTTP,
  base_url: "http://fuse.test",
  token: "test-token",
  req_options: [retry: false]

# Disable swoosh api client as it is only required for production adapters
config :swoosh, :api_client, false

# Print only warnings and errors during test
config :logger, level: :warning

# Initialize plugs at runtime for faster test compilation
config :phoenix, :plug_init_mode, :runtime

# Enable helpful, but potentially expensive runtime checks
config :phoenix_live_view,
  enable_expensive_runtime_checks: true
