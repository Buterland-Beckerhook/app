defmodule BbhWeb.DevClock do
  @moduledoc """
  The visible half of the dev time travel (`BbhWeb.Plugs.DevClock` does the
  shifting): the "Simulierte Zeit" banner and the moments worth jumping to, derived
  from the festival `Bbh.Calendar.dev_festival/1` picks.

  With programme items (children) the moments come from the items themselves — just
  before the first one, while it runs, before each later day's first item, inside an
  overnight item, around the last item's end. Without children they fall back to
  fixed times on the festival's days.
  """
  use BbhWeb, :html

  alias BbhWeb.Format

  @doc "Moments for the banner: `[%{at: DateTime, hint: String}]`, chronological."
  def jump_points(nil), do: []

  def jump_points(%{children: [_ | _] = children} = fest) do
    first = hd(children)
    last_end = children |> Enum.map(&finish/1) |> Enum.max(DateTime)

    later_day_openers =
      children
      |> Enum.chunk_by(&DateTime.to_date(&1.starts_at))
      |> Enum.map(&hd/1)
      |> Enum.drop(1)

    overnight = Enum.find(children, &overnight?/1)

    [
      point(at(Date.add(DateTime.to_date(fest.starts_at), -7), 12, 0), "eine Woche vorher"),
      point(DateTime.add(first.starts_at, -60), "kurz vor „#{first.title}“"),
      point(midpoint(first), "„#{first.title}“ läuft"),
      Enum.map(
        later_day_openers,
        &point(DateTime.add(&1.starts_at, -300), "kurz vor „#{&1.title}“")
      ),
      overnight &&
        point(DateTime.add(overnight.ends_at, -1800), "nachts, „#{overnight.title}“ läuft"),
      point(DateTime.add(last_end, -60), "kurz vor Schluss"),
      point(DateTime.add(last_end, 60), "kurz nach Schluss"),
      point(DateTime.add(last_end, 10 * 3600), "nach dem Fest")
    ]
    |> finalize()
  end

  def jump_points(%{starts_at: starts_at, ends_at: ends_at}) do
    first = DateTime.to_date(starts_at)
    last = DateTime.to_date(ends_at || starts_at)
    day = &Date.add(first, &1)

    [
      point(at(day.(-7), 12, 0), "eine Woche vorher"),
      point(at(first, 13, 59), "erster Tag, nachmittags"),
      point(at(first, 14, 30), "erster Tag, nachmittags"),
      point(at(day.(1), 9, 25), "zweiter Tag, morgens"),
      point(at(day.(1), 15, 0), "zweiter Tag, nachmittags"),
      point(at(day.(2), 1, 30), "nachts"),
      point(at(day.(2), 6, 5), "dritter Tag, früh"),
      point(at(last, 23, 30), "letzter Tag, spät"),
      point(at(Date.add(last, 1), 1, 59), "Ende der Nacht"),
      point(at(Date.add(last, 1), 2, 1), "Ende der Nacht"),
      point(at(Date.add(last, 1), 12, 0), "nach dem Fest")
    ]
    |> finalize()
  end

  @doc """
  Moments for the `/dev/zeitreise` grid: the jump points plus every programme item's
  start, start + 1 min and end.
  """
  def overview_points(nil), do: []

  def overview_points(fest) do
    item_points =
      Enum.flat_map(fest.children, fn c ->
        [
          point(c.starts_at, "Beginn „#{c.title}“"),
          point(DateTime.add(c.starts_at, 60), "„#{c.title}“ + 1 min"),
          c.ends_at && point(c.ends_at, "Ende „#{c.title}“")
        ]
      end)

    finalize(jump_points(fest) ++ item_points)
  end

  @doc "The `?jetzt=` value for a moment."
  def param(%DateTime{} = dt), do: Calendar.strftime(dt, "%Y-%m-%dT%H:%M")

  attr :now, DateTime, required: true
  attr :path, :string, required: true

  @doc "Fixed banner shown on every page while a simulated time is active."
  def banner(assigns) do
    assigns = assign(assigns, :points, jump_points(Bbh.Calendar.dev_festival()))

    ~H"""
    <div
      id="dev-clock-banner"
      class="fixed inset-x-0 bottom-0 z-[100] border-t-4 border-warning-content/40 bg-warning text-sm text-warning-content shadow-2xl"
    >
      <details class="mx-auto max-w-6xl px-4 py-2">
        <summary class="flex cursor-pointer flex-wrap items-center gap-x-3 gap-y-1">
          <span class="font-bold tracking-wide uppercase">Simulierte Zeit</span>
          <span class="font-semibold tabular-nums">{Format.de_short_datetime(@now)}</span>
          <a href={"#{@path}?jetzt="} class="underline">Zurücksetzen</a>
          <a href="/dev/zeitreise" class="underline">Zeitreise</a>
          <span :if={@points != []} class="opacity-70">Sprungmarken ▾</span>
        </summary>
        <div class="mt-2 flex flex-wrap gap-1.5 pb-1">
          <a
            :for={p <- @points}
            href={"#{@path}?jetzt=#{param(p.at)}"}
            title={p.hint}
            class={[
              "rounded-full border border-warning-content/30 px-2.5 py-1 tabular-nums hover:bg-warning-content/10",
              DateTime.compare(p.at, @now) == :eq && "bg-warning-content/20 font-semibold"
            ]}
          >
            {Format.de_short_datetime(p.at)}
            <span class="opacity-70">· {p.hint}</span>
          </a>
        </div>
      </details>
    </div>
    """
  end

  defp point(%DateTime{} = at, hint), do: %{at: at, hint: hint}

  defp finalize(points) do
    points
    |> List.flatten()
    |> Enum.reject(&is_nil/1)
    |> Enum.sort_by(& &1.at, DateTime)
    |> Enum.uniq_by(& &1.at)
  end

  defp at(%Date{} = date, hour, minute),
    do: DateTime.new!(date, Time.new!(hour, minute, 0), "Etc/UTC")

  defp finish(%{ends_at: %DateTime{} = ends_at}), do: ends_at
  defp finish(%{starts_at: starts_at}), do: starts_at

  defp midpoint(%{starts_at: s, ends_at: %DateTime{} = e}),
    do: DateTime.add(s, div(DateTime.diff(e, s), 2))

  defp midpoint(%{starts_at: s}), do: DateTime.add(s, 1800)

  defp overnight?(%{starts_at: s, ends_at: %DateTime{} = e}),
    do: Date.compare(DateTime.to_date(e), DateTime.to_date(s)) == :gt

  defp overnight?(_), do: false
end
