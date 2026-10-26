defmodule Bbh.Repo.Migrations.AddShowEndToEvents do
  use Ecto.Migration

  # Some events have no fixed end (a litter pick-up "takes about three hours"). The end
  # still goes into iCal, so a calendar entry is bounded, but the site leaves it out so a
  # reader isn't told they have to leave at a given time.
  def change do
    alter table(:events) do
      add :show_end, :boolean, null: false, default: true
    end
  end
end
