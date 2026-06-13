defmodule Fuse.Application do
  # See https://hexdocs.pm/elixir/Application.html
  # for more information on OTP Applications
  @moduledoc false

  use Application

  require Logger

  @impl true
  def start(_type, _args) do
    warn_if_insecure_prod()

    children = [
      FuseWeb.Telemetry,
      Fuse.Repo,
      {Ecto.Migrator,
       repos: Application.fetch_env!(:fuse, :ecto_repos), skip: skip_migrations?()},
      {DNSCluster, query: Application.get_env(:fuse, :dns_cluster_query) || :ignore},
      {Phoenix.PubSub, name: Fuse.PubSub},
      # Event streaming: registry (one consumer per vm_id) + its dynamic supervisor.
      {Registry, keys: :unique, name: Fuse.EventStream.Registry},
      Fuse.EventStream.Supervisor,
      # Start to serve requests, typically the last entry
      FuseWeb.Endpoint
    ]

    # See https://hexdocs.pm/elixir/Supervisor.html
    # for other strategies and supported options
    opts = [strategy: :one_for_one, name: Fuse.Supervisor]
    Supervisor.start_link(children, opts)
  end

  @doc """
  Warn (loudly, but non-fatally) when running in production with no inbound API
  token configured — the `/api/v1` surface is then unauthenticated. Booting is
  still allowed (operator's choice); this just makes the risk visible in logs.
  """
  @spec warn_if_insecure_prod() :: :ok
  def warn_if_insecure_prod do
    token = Application.get_env(:fuse, FuseWeb.Plugs.ApiAuth, [])[:token]

    if Application.get_env(:fuse, :env) == :prod and token in [nil, ""] do
      Logger.warning(
        "CONTROL_PLANE_TOKEN is unset; /api/v1 is UNAUTHENTICATED. " <>
          "Set CONTROL_PLANE_TOKEN to require inbound auth."
      )
    end

    :ok
  end

  # Tell Phoenix to update the endpoint configuration
  # whenever the application is updated.
  @impl true
  def config_change(changed, _new, removed) do
    FuseWeb.Endpoint.config_change(changed, removed)
    :ok
  end

  defp skip_migrations?() do
    # By default, sqlite migrations are run when using a release
    System.get_env("RELEASE_NAME") == nil
  end
end
