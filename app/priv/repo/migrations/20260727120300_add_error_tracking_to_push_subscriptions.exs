defmodule Bbh.Repo.Migrations.AddErrorTrackingToPushSubscriptions do
  use Ecto.Migration

  def change do
    alter table(:push_subscriptions) do
      # Consecutive non-fatal send failures (reset to 0 on a successful send) and
      # when the last failure occurred — surfaced in the admin subscriptions view.
      add :error_count, :integer, null: false, default: 0
      add :last_error_at, :utc_datetime
    end
  end
end
