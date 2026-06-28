# Integration tests (tagged :integration) hit a REAL fuse instance and are
# excluded by default. Run them with a live fuse and:
#
#     FUSE_BASE_URL=http://localhost:8080 FUSE_TOKEN=... mix test --include integration
ExUnit.start(exclude: [:integration])
Ecto.Adapters.SQL.Sandbox.mode(Fuse.Repo, :manual)
