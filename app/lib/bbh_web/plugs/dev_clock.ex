defmodule BbhWeb.Plugs.DevClock do
  @moduledoc """
  Dev-only time travel: lets a request see the site as it would look at another
  moment, without waiting for it or deploying anywhere.

  Plugged in the endpoint, behind `config :bbh, :dev_clock` (dev only), so it never
  exists in prod or test. It shifts `Bbh.Time.now/1` by putting an offset into the
  **request process's** dictionary:

    * `?jetzt=2026-07-19T09:25` (local wall-clock, seconds optional, a bare date means
      00:00) — simulate that moment for this request and remember it in the session;
    * `?jetzt=` (empty) — forget the remembered moment;
    * `?jetzt_temp=1` alongside `jetzt` — simulate without touching the session (the
      iframes of `/dev/zeitreise` use it so frames don't overwrite each other);
    * no parameter — the remembered moment, if any.

  The simulated moment is a fixed point: every page load shows exactly that time (the
  homepage countdown still ticks from it, via `data-countdown-now`).

  It runs on every request, not just the browser pipeline, because the connection
  process — and with it the dictionary — is reused for keep-alive requests: a stale
  offset must be cleared, not just left out.

  Only the request process is shifted. Oban jobs and LiveView processes run elsewhere
  and keep the real time, so time travel can never send a real push; the admin
  LiveViews are deliberately out of scope.
  """
  @behaviour Plug
  import Plug.Conn

  @session_key "dev_clock_now"

  @impl true
  def init(opts), do: opts

  @impl true
  def call(conn, _opts) do
    Process.delete(Bbh.Time.offset_key())
    conn = conn |> fetch_session() |> fetch_query_params()

    {simulated, conn} = simulated_now(conn, conn.query_params)

    if simulated do
      Process.put(Bbh.Time.offset_key(), DateTime.diff(simulated, Bbh.Time.real_now()))

      conn
      |> assign(:simulated_now, simulated)
      # A /dev/zeitreise frame: the grid labels it, so the root layout skips the banner.
      |> assign(:dev_clock_frame, Map.has_key?(conn.query_params, "jetzt_temp"))
    else
      conn
    end
  end

  defp simulated_now(conn, %{"jetzt" => ""}), do: {nil, delete_session(conn, @session_key)}

  defp simulated_now(conn, %{"jetzt" => value} = params) when is_binary(value) do
    case parse(value) do
      {:ok, dt} when is_map_key(params, "jetzt_temp") -> {dt, conn}
      {:ok, dt} -> {dt, put_session(conn, @session_key, value)}
      :error -> {nil, conn}
    end
  end

  defp simulated_now(conn, _params) do
    case parse(get_session(conn, @session_key)) do
      {:ok, dt} -> {dt, conn}
      :error -> {nil, conn}
    end
  end

  @doc """
  Parses a `jetzt` value — `YYYY-MM-DD`, `YYYY-MM-DDTHH:MM` or `…:SS` — as a local
  wall-clock time tagged UTC, the shape `Bbh.Time.now/1` returns.
  """
  def parse(value) when is_binary(value) do
    iso =
      case String.length(value) do
        10 -> value <> "T00:00:00"
        16 -> value <> ":00"
        _ -> value
      end

    case NaiveDateTime.from_iso8601(iso) do
      {:ok, naive} ->
        {:ok, naive |> NaiveDateTime.truncate(:second) |> DateTime.from_naive!("Etc/UTC")}

      {:error, _} ->
        :error
    end
  end

  def parse(_), do: :error
end
