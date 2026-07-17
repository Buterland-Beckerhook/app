defmodule BbhWeb.Plugs.TrackPageView do
  @moduledoc """
  Records a page view for public GET requests into `Bbh.Analytics`.

  Runs a `register_before_send/2` callback so the response status and
  content-type are known, and hands the actual DB write to `Bbh.TaskSupervisor`
  so the request is never blocked. Skips the admin area, API, static assets, and
  obvious bots.

  Config (`config :bbh, __MODULE__, ...`):
    * `enabled:` — set `false` to turn recording off (default on).
    * `async:` — set `false` to write inline instead of via the task
      supervisor (used in tests so the write stays in the SQL sandbox).
  """
  import Plug.Conn

  alias BbhWeb.RateLimit

  @skip_prefixes ["/admin", "/users", "/api", "/dev", "/assets", "/images", "/fonts"]
  @skip_paths ["/favicon.ico", "/robots.txt", "/sw.js", "/manifest.webmanifest"]
  @bot_re ~r/bot|crawl|spider|slurp|mediapartners|facebookexternalhit|embedly|preview|scrapy|curl|wget|python-requests|headless|monitor|uptime/i

  def init(opts), do: opts

  def call(conn, _opts) do
    if enabled?() and trackable_request?(conn) do
      register_before_send(conn, &record/1)
    else
      conn
    end
  end

  defp trackable_request?(conn) do
    conn.method == "GET" and not skipped_path?(conn.request_path) and not bot?(conn)
  end

  defp record(conn) do
    if conn.status == 200 and html?(conn) do
      attrs = %{
        path: conn.request_path,
        referrer_host: external_referrer_host(conn),
        visitor_hash: visitor_hash(conn)
      }

      if async?() do
        Task.Supervisor.start_child(Bbh.TaskSupervisor, fn -> Bbh.Analytics.record(attrs) end)
      else
        Bbh.Analytics.record(attrs)
      end
    end

    conn
  end

  defp skipped_path?(path) do
    path in @skip_paths or Enum.any?(@skip_prefixes, &String.starts_with?(path, &1))
  end

  defp bot?(conn) do
    case get_req_header(conn, "user-agent") do
      [ua | _] -> Regex.match?(@bot_re, ua)
      _ -> true
    end
  end

  defp html?(conn) do
    case get_resp_header(conn, "content-type") do
      [ct | _] -> String.contains?(ct, "text/html")
      _ -> false
    end
  end

  # The referrer host, only when it is a different site than our own.
  defp external_referrer_host(conn) do
    with [referer | _] <- get_req_header(conn, "referer"),
         %URI{host: host} when is_binary(host) <- URI.parse(referer),
         true <- host != conn.host do
      host
    else
      _ -> nil
    end
  end

  # Non-reversible daily-salted digest of the client; the same visitor yields the
  # same hash within a day and a different one the next, so it can't be tracked
  # across days or reversed to an IP.
  defp visitor_hash(conn) do
    ua =
      case get_req_header(conn, "user-agent") do
        [value | _] -> value
        _ -> ""
      end

    material = [secret(), Date.to_iso8601(Date.utc_today()), RateLimit.client_ip(conn), ua]
    :crypto.hash(:sha256, Enum.join(material, "|")) |> Base.encode16(case: :lower)
  end

  defp secret do
    Application.get_env(:bbh, BbhWeb.Endpoint)[:secret_key_base] || "bbh-analytics-fallback"
  end

  defp enabled?, do: Application.get_env(:bbh, __MODULE__, [])[:enabled] != false
  defp async?, do: Application.get_env(:bbh, __MODULE__, [])[:async] != false
end
