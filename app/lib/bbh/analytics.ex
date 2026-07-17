defmodule Bbh.Analytics do
  @moduledoc """
  Lightweight, privacy-friendly in-app analytics — a self-hosted replacement
  for Matomo. Stores only aggregated, PII-free daily counters:

    * page views per path
    * external referrer hosts
    * rough unique visitors (one row per daily-salted visitor hash)

  Recording is fire-and-forget (see `BbhWeb.Plugs.TrackPageView`); the read
  side powers the admin dashboard.
  """
  import Ecto.Query

  alias Bbh.Analytics.{DailyPageView, DailyReferrer, DailyVisitor}
  alias Bbh.Repo

  @path_max 255

  @doc """
  Record a single page view. Expects `%{path:, referrer_host:, visitor_hash:}`
  (and optional `:day`, defaulting to today, UTC). Best-effort: any error is
  swallowed so tracking never affects the request.
  """
  def record(attrs) do
    day = Map.get(attrs, :day, Date.utc_today())
    path = attrs |> Map.get(:path, "/") |> truncate(@path_max)

    Repo.insert(%DailyPageView{day: day, path: path, views: 1},
      on_conflict: [inc: [views: 1]],
      conflict_target: [:day, :path]
    )

    case attrs[:referrer_host] do
      host when is_binary(host) and host != "" ->
        Repo.insert(%DailyReferrer{day: day, host: truncate(host, @path_max), views: 1},
          on_conflict: [inc: [views: 1]],
          conflict_target: [:day, :host]
        )

      _ ->
        :ok
    end

    case attrs[:visitor_hash] do
      hash when is_binary(hash) and hash != "" ->
        Repo.insert(%DailyVisitor{day: day, visitor_hash: hash},
          on_conflict: :nothing,
          conflict_target: [:day, :visitor_hash]
        )

      _ ->
        :ok
    end

    :ok
  rescue
    error ->
      require Logger
      Logger.warning("Analytics.record failed: #{inspect(error)}")
      :error
  end

  @doc "Total page views and rough visits (summed daily uniques) in `[from, to]`."
  def summary(from, to) do
    views =
      Repo.one(
        from p in DailyPageView,
          where: p.day >= ^from and p.day <= ^to,
          select: coalesce(sum(p.views), 0)
      )

    visits =
      Repo.one(
        from v in DailyVisitor, where: v.day >= ^from and v.day <= ^to, select: count(v.id)
      )

    %{views: views, visits: visits}
  end

  @doc "Top viewed paths in `[from, to]` as `[%{path:, views:}]`."
  def top_pages(from, to, limit \\ 10) do
    Repo.all(
      from p in DailyPageView,
        where: p.day >= ^from and p.day <= ^to,
        group_by: p.path,
        order_by: [desc: sum(p.views)],
        limit: ^limit,
        select: %{path: p.path, views: sum(p.views)}
    )
  end

  @doc "Top external referrer hosts in `[from, to]` as `[%{host:, views:}]`."
  def top_referrers(from, to, limit \\ 10) do
    Repo.all(
      from r in DailyReferrer,
        where: r.day >= ^from and r.day <= ^to,
        group_by: r.host,
        order_by: [desc: sum(r.views)],
        limit: ^limit,
        select: %{host: r.host, views: sum(r.views)}
    )
  end

  @doc "Daily page-view totals across `[from, to]`, gap-filled, oldest first."
  def views_by_day(from, to) do
    rows =
      Repo.all(
        from p in DailyPageView,
          where: p.day >= ^from and p.day <= ^to,
          group_by: p.day,
          select: {p.day, sum(p.views)}
      )
      |> Map.new()

    fill_days(from, to, rows)
  end

  @doc "Daily unique-visitor counts across `[from, to]`, gap-filled, oldest first."
  def visitors_by_day(from, to) do
    rows =
      Repo.all(
        from v in DailyVisitor,
          where: v.day >= ^from and v.day <= ^to,
          group_by: v.day,
          select: {v.day, count(v.id)}
      )
      |> Map.new()

    fill_days(from, to, rows)
  end

  defp fill_days(from, to, counts) do
    Date.range(from, to)
    |> Enum.map(fn day -> %{day: day, count: Map.get(counts, day, 0)} end)
  end

  defp truncate(str, max) when is_binary(str), do: String.slice(str, 0, max)
  defp truncate(_, _), do: ""
end
