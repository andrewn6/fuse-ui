defmodule Fuse.Repo do
  use Ecto.Repo,
    otp_app: :fuse,
    adapter: Ecto.Adapters.SQLite3
end
