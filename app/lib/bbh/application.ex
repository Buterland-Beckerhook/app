defmodule Bbh.Application do
  # See https://elixir.hexdocs.pm/Application.html
  # for more information on OTP Applications
  @moduledoc false

  use Application

  require Logger

  @impl true
  def start(_type, _args) do
    log_mail_config()

    children = [
      BbhWeb.Telemetry,
      Bbh.Repo,
      {DNSCluster, query: Application.get_env(:bbh, :dns_cluster_query) || :ignore},
      {Phoenix.PubSub, name: Bbh.PubSub},
      {BbhWeb.RateLimit, clean_period: :timer.minutes(10)},
      Bbh.Altcha.ReplayCache,
      {Task.Supervisor, name: Bbh.TaskSupervisor},
      {Oban, Application.fetch_env!(:bbh, Oban)},
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

  # Log the resolved mailer target at boot so deployment logs confirm whether the
  # SMTP env vars were actually injected (a blank relay is itself the bug). Never
  # logs credentials — only adapter, relay host and port.
  defp log_mail_config do
    cfg = Application.get_env(:bbh, Bbh.Mailer, [])

    Logger.info(
      "[mail] configured adapter=#{inspect(cfg[:adapter])} " <>
        "relay=#{inspect(cfg[:relay])} port=#{inspect(cfg[:port])}"
    )
  end
end
