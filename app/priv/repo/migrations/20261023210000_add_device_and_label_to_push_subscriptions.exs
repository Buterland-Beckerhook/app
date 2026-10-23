defmodule Bbh.Repo.Migrations.AddDeviceAndLabelToPushSubscriptions do
  use Ecto.Migration

  # `device`: short browser/OS summary taken from the subscribe request's User-Agent
  # (never the raw header). `label`: a name an admin gives their own device from that
  # device's settings dialog, so it can be told apart in /admin/push.
  def change do
    alter table(:push_subscriptions) do
      add :device, :string
      add :label, :string
    end
  end
end
