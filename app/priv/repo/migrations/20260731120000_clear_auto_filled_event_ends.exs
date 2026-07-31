defmodule Bbh.Repo.Migrations.ClearAutoFilledEventEnds do
  use Ecto.Migration

  # Older event changesets auto-filled a missing end with 23:59 of the start day.
  # That default is gone; wipe the ends it produced so those events show start-only
  # again. Targets exactly the auto-filled set: non-all-day events whose end is
  # 23:59:00 on the same calendar day as the start. Irreversible (the original
  # "no end" and a genuine 23:59 end are indistinguishable), so `down` is a no-op.
  def up do
    execute("""
    UPDATE events SET "end" = NULL
    WHERE "end" IS NOT NULL
      AND all_day = false
      AND date_trunc('day', "end") = date_trunc('day', "start")
      AND to_char("end", 'HH24:MI:SS') = '23:59:00'
    """)
  end

  def down, do: :ok
end
