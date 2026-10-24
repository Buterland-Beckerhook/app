# Demo festival for the event programme and the dev time travel (/dev/zeitreise):
# "Schützenfest (Demo)", Sat 18 – Tue 21 July 2026, with the 2026 Festprogramm as
# programme items, plus a standalone event a week after it.
#
#     make seed-demo        # = mix run priv/repo/seeds/schuetzenfest_demo.exs
#
# Idempotent: the previous demo festival (with its items and reminders) and the
# standalone demo event are deleted first, so it can be re-run any time, also after
# `make reset-db` or `make seed`. It only ever touches its own *-demo slugs and the
# demo locations it creates — never the real Schützenfest of a prod snapshot.
#
# Edge cases for visual checks: one canceled item (with reason), one draft item
# (must stay invisible) and a reminder on the Gottesdienst. All dates lie in July
# 2026, so nothing here can come due and push for real.

import Ecto.Query

alias Bbh.Calendar
alias Bbh.Calendar.{Event, Location}
alias Bbh.Repo

year = 2026
fest_slug = "schuetzenfest-demo"
after_slug = "koenigsfruehstueck-demo"

Repo.delete_all(
  from e in Event, where: e.year == ^year and e.slug in ^[fest_slug, after_slug] and is_nil(e.parent_id)
)

location = fn key, name ->
  case Repo.get_by(Location, key: key) do
    %Location{} = loc ->
      loc

    nil ->
      {:ok, loc} = Calendar.create_location(%{key: key, name: name, city: "Rheine"})
      loc
  end
end

festzelt = location.("festzelt", "Festzelt")
festplatz = location.("festplatz", "Festplatz")
dinkelhof = location.("dinkelhof", "Dinkelhof")
schulhof = location.("schulhof-buterlandschule", "Schulhof Buterlandschule")

create! = fn attrs ->
  case Calendar.create_event(attrs) do
    {:ok, event} -> event
    {:error, changeset} -> raise "demo seed: #{inspect(changeset.errors)} for #{attrs.title}"
  end
end

fest =
  create!.(%{
    status: "published",
    title: "Schützenfest (Demo)",
    slug: fest_slug,
    all_day: true,
    starts_at: ~U[2026-07-18 00:00:00Z],
    ends_at: ~U[2026-07-21 00:00:00Z],
    location_id: festzelt.id,
    body: "<p>Demo-Fest für die Zeitreise (<code>/dev/zeitreise</code>).</p>"
  })

# {slug, title, starts_at, ends_at, location, extra attrs}
programme = [
  {"kinderfest", "Kinderfest mit anschließender Tütenausgabe", ~U[2026-07-18 14:00:00Z],
   ~U[2026-07-18 18:00:00Z], festplatz, %{}},
  {"antreten-samstag", "Antreten der Schützen", ~U[2026-07-18 19:45:00Z],
   ~U[2026-07-18 20:00:00Z], schulhof, %{}},
  {"vogelschiessen-jungschuetzen",
   "Abmarsch zum Festplatz, Vogelschießen der Jungschützen, Tanz", ~U[2026-07-18 20:00:00Z],
   ~U[2026-07-19 02:00:00Z], festplatz, %{}},
  {"gottesdienst", "Gottesdienst", ~U[2026-07-19 09:30:00Z], ~U[2026-07-19 10:30:00Z],
   festzelt,
   %{
     body: "<p>Ökumenischer Gottesdienst im Festzelt.</p>",
     reminders: [%{lead_days: 1, text: "Morgen um 9:30 Uhr: Gottesdienst im Festzelt"}]
   }},
  {"fruehschoppen", "Frühschoppenkonzert, Jubilarehrungen", ~U[2026-07-19 10:30:00Z],
   ~U[2026-07-19 12:30:00Z], festzelt, %{}},
  {"antreten-sonntag", "Antreten aller Schützen", ~U[2026-07-19 14:15:00Z],
   ~U[2026-07-19 14:30:00Z], schulhof, %{}},
  {"festumzug", "Begrüßung S.M., Totenehrung, Festumzug", ~U[2026-07-19 14:30:00Z],
   ~U[2026-07-19 19:30:00Z], festzelt, %{}},
  {"festball-sonntag", "Großer Festball mit Fernandos", ~U[2026-07-19 20:00:00Z],
   ~U[2026-07-20 02:00:00Z], festzelt, %{}},
  {"grosses-wecken", "Großes Wecken", ~U[2026-07-20 06:00:00Z], ~U[2026-07-20 10:30:00Z],
   nil, %{}},
  {"antreten-montag", "Antreten der Schützen", ~U[2026-07-20 10:30:00Z],
   ~U[2026-07-20 12:30:00Z], dinkelhof, %{}},
  {"koenigsschiessen", "Königsschießen", ~U[2026-07-20 12:30:00Z], ~U[2026-07-20 16:30:00Z],
   festplatz, %{}},
  {"kroenung", "Krönung, Festball mit Start-Up", ~U[2026-07-20 20:00:00Z],
   ~U[2026-07-21 02:00:00Z], festzelt, %{}},
  {"schnitzelessen", "Schnitzelessen", ~U[2026-07-21 12:00:00Z], ~U[2026-07-21 18:00:00Z],
   dinkelhof, %{status: "canceled", cancel_reason: "Fällt in diesem Jahr leider aus."}},
  {"kehraus", "Kehraus mit DJ Thorsten", ~U[2026-07-21 20:00:00Z], ~U[2026-07-22 02:00:00Z],
   festzelt, %{}},
  {"aufraeumen", "Aufräumen am Festplatz (Entwurf)", ~U[2026-07-21 10:00:00Z],
   ~U[2026-07-21 11:00:00Z], festplatz, %{status: "draft"}}
]

for {slug, title, starts_at, ends_at, loc, extra} <- programme do
  %{
    parent_id: fest.id,
    status: "published",
    slug: slug,
    title: title,
    starts_at: starts_at,
    ends_at: ends_at,
    location_id: loc && loc.id
  }
  |> Map.merge(extra)
  |> create!.()
end

create!.(%{
  status: "published",
  title: "Königsfrühstück (Demo)",
  slug: after_slug,
  starts_at: ~U[2026-07-26 10:00:00Z],
  ends_at: ~U[2026-07-26 13:00:00Z],
  location_id: dinkelhof.id
})

IO.puts("Demo festival seeded: /termine/#{year}/#{fest_slug} (#{length(programme)} items)")
