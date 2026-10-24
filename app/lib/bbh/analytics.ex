defmodule Bbh.Analytics do
  @moduledoc """
  Lightweight, privacy-friendly in-app analytics. Stores only aggregated, PII-free
  daily counters:

    * page views per path
    * external referrer hosts
    * rough unique visitors (one row per daily-salted visitor hash)

  Recording is fire-and-forget (see `BbhWeb.Plugs.TrackPageView`); the read
  side powers the admin dashboard.

  The visitor hashes (`DailyVisitor`, `IcalFetch`) are pseudonymous rather than
  anonymous: the daily salt is derived from `secret_key_base`, so whoever holds it could
  re-derive a day's hashes from candidate IPs. They are therefore only kept for
  seven days — `roll_up/1` (run nightly by `Bbh.Workers.AnalyticsRollup`) folds every
  older day into `DailyVisitorCount` / `IcalFetchCount` and deletes the hash rows. The
  read functions below combine both, so a range spanning the cut-over counts the same
  as before.
  """
  import Ecto.Query

  alias Bbh.Analytics.{
    DailyPageView,
    DailyReferrer,
    DailyVisitor,
    DailyVisitorCount,
    IcalFetch,
    IcalFetchCount
  }

  alias Bbh.Repo

  @path_max 255

  # Days a visitor hash is kept before `roll_up/1` replaces it with the day's total.
  @retention_days 7

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

  @doc """
  Record one retrieval of the iCal subscription feed. Expects `%{visitor_hash:}`, plus
  optional `:client` (family key from `Bbh.Analytics.IcalClient`) and `:day`
  (defaulting to today, UTC). Increments the client's daily fetch counter.
  Best-effort: any error is swallowed.
  """
  def record_ical(attrs) do
    day = Map.get(attrs, :day, Date.utc_today())

    case attrs[:visitor_hash] do
      hash when is_binary(hash) and hash != "" ->
        # The hash already covers the User-Agent, so a row's client never changes —
        # only the counter needs updating on conflict.
        Repo.insert(
          %IcalFetch{day: day, visitor_hash: hash, fetches: 1, client: attrs[:client]},
          on_conflict: [inc: [fetches: 1]],
          conflict_target: [:day, :visitor_hash]
        )

      _ ->
        :ok
    end

    :ok
  rescue
    error ->
      require Logger
      Logger.warning("Analytics.record_ical failed: #{inspect(error)}")
      :error
  end

  @doc """
  Replace the per-hash rows of every day older than `retention_days` (default
  #{@retention_days}) with that day's totals, then delete them. Runs in one transaction,
  so a failure leaves both sides as they were.

  Additive: a day that somehow already has a total gets the remaining rows added to it
  rather than overwriting it — the rows are deleted in the same step, so nothing is
  counted twice. Returns `{:ok, %{visitors: deleted_rows, ical: deleted_rows}}`.
  """
  def roll_up(retention_days \\ @retention_days) do
    cutoff = Date.add(Date.utc_today(), -retention_days)

    Repo.transaction(fn ->
      visitor_totals =
        from v in DailyVisitor,
          where: v.day < ^cutoff,
          group_by: v.day,
          select: %{day: v.day, visitors: count(v.id)}

      Repo.insert_all(DailyVisitorCount, visitor_totals,
        on_conflict:
          from(c in DailyVisitorCount,
            update: [set: [visitors: fragment("? + EXCLUDED.visitors", c.visitors)]]
          ),
        conflict_target: [:day]
      )

      ical_totals =
        from f in IcalFetch,
          where: f.day < ^cutoff,
          group_by: [f.day, f.client],
          select: %{day: f.day, client: f.client, clients: count(f.id), fetches: sum(f.fetches)}

      Repo.insert_all(IcalFetchCount, ical_totals,
        on_conflict:
          from(c in IcalFetchCount,
            update: [
              set: [
                clients: fragment("? + EXCLUDED.clients", c.clients),
                fetches: fragment("? + EXCLUDED.fetches", c.fetches)
              ]
            ]
          ),
        conflict_target: [:day, :client]
      )

      {visitors, _} = Repo.delete_all(from v in DailyVisitor, where: v.day < ^cutoff)
      {ical, _} = Repo.delete_all(from f in IcalFetch, where: f.day < ^cutoff)

      %{visitors: visitors, ical: ical}
    end)
  end

  @doc """
  iCal feed retrievals in `[from, to]`: total `fetches` and `subscribers` (the
  peak daily unique-client count, a rough proxy for the number of subscriptions).
  """
  def ical_summary(from, to) do
    fetches =
      Repo.one(
        from f in IcalFetch,
          where: f.day >= ^from and f.day <= ^to,
          select: coalesce(sum(f.fetches), 0)
      ) +
        Repo.one(
          from c in IcalFetchCount,
            where: c.day >= ^from and c.day <= ^to,
            select: coalesce(sum(c.fetches), 0)
        )

    live =
      Repo.all(
        from f in IcalFetch,
          where: f.day >= ^from and f.day <= ^to,
          group_by: f.day,
          select: {f.day, count(f.id)}
      )

    rolled_up =
      Repo.all(
        from c in IcalFetchCount,
          where: c.day >= ^from and c.day <= ^to,
          group_by: c.day,
          select: {c.day, sum(c.clients)}
      )

    subscribers = (live ++ rolled_up) |> sum_by_key() |> Map.values() |> Enum.max(fn -> 0 end)

    %{fetches: fetches, subscribers: subscribers}
  end

  @doc """
  iCal feed retrievals in `[from, to]` broken down by calendar-client family, as
  `[%{client:, label:, subscribers:, fetches:}]` — `subscribers` is the family's peak
  daily unique-client count (as in `ical_summary/2`). Sorted by subscribers, then
  fetches, both descending.
  """
  def ical_clients(from, to) do
    live =
      Repo.all(
        from f in IcalFetch,
          where: f.day >= ^from and f.day <= ^to,
          group_by: [f.client, f.day],
          select: {{f.client, f.day}, {count(f.id), sum(f.fetches)}}
      )

    rolled_up =
      Repo.all(
        from c in IcalFetchCount,
          where: c.day >= ^from and c.day <= ^to,
          select: {{c.client, c.day}, {c.clients, c.fetches}}
      )

    (live ++ rolled_up)
    |> Enum.reduce(%{}, fn {key, {clients, fetches}}, acc ->
      Map.update(acc, key, {clients, fetches}, fn {c, f} -> {c + clients, f + fetches} end)
    end)
    |> Enum.map(fn {{client, _day}, {clients, fetches}} -> {client, clients, fetches} end)
    |> Enum.group_by(&elem(&1, 0))
    |> Enum.map(fn {client, days} ->
      %{
        client: client,
        label: Bbh.Analytics.IcalClient.label(client),
        subscribers: days |> Enum.map(&elem(&1, 1)) |> Enum.max(),
        fetches: days |> Enum.map(&elem(&1, 2)) |> Enum.sum()
      }
    end)
    |> Enum.sort_by(&{&1.subscribers, &1.fetches}, :desc)
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
      ) +
        Repo.one(
          from c in DailyVisitorCount,
            where: c.day >= ^from and c.day <= ^to,
            select: coalesce(sum(c.visitors), 0)
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
    live =
      Repo.all(
        from v in DailyVisitor,
          where: v.day >= ^from and v.day <= ^to,
          group_by: v.day,
          select: {v.day, count(v.id)}
      )

    rolled_up =
      Repo.all(
        from c in DailyVisitorCount,
          where: c.day >= ^from and c.day <= ^to,
          select: {c.day, c.visitors}
      )

    fill_days(from, to, sum_by_key(live ++ rolled_up))
  end

  # `[{key, n}]` -> `%{key => sum of n}`. Live hash rows and rolled-up totals never cover
  # the same day, but adding rather than overwriting keeps that an assumption-free merge.
  defp sum_by_key(pairs) do
    Enum.reduce(pairs, %{}, fn {key, n}, acc -> Map.update(acc, key, n, &(&1 + n)) end)
  end

  defp fill_days(from, to, counts) do
    Date.range(from, to)
    |> Enum.map(fn day -> %{day: day, count: Map.get(counts, day, 0)} end)
  end

  defp truncate(str, max) when is_binary(str), do: String.slice(str, 0, max)
  defp truncate(_, _), do: ""
end
