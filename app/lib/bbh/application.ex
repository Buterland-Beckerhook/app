defmodule Bbh.Application do
  # See https://elixir.hexdocs.pm/Application.html
  # for more information on OTP Applications
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    children = [
      BbhWeb.Telemetry,
      Bbh.Repo,
      {DNSCluster, query: Application.get_env(:bbh, :dns_cluster_query) || :ignore},
      {Phoenix.PubSub, name: Bbh.PubSub},
      {BbhWeb.RateLimit, clean_period: :timer.minutes(10)},
      Bbh.Altcha.ReplayCache,
      {Task.Supervisor, name: Bbh.TaskSupervisor},
      # Start a worker by calling: Bbh.Worker.start_link(arg)
      # {Bbh.Worker, arg},
      # Start to serve requests, typically the last entry
      BbhWeb.Endpoint
    ]

    # See https://elixir.hexdocs.pm/Supervisor.html
    # for other strategies and supported options
    opts = [strategy: :one_for_one, name: Bbh.Supervisor]
    Supervisor.start_link(children, opts)
  end

  # Tell Phoenix to update the endpoint configuration
  # whenever the application is updated.
  @impl true
  def config_change(changed, _new, removed) do
    BbhWeb.Endpoint.config_change(changed, removed)
    :ok
  end
end
