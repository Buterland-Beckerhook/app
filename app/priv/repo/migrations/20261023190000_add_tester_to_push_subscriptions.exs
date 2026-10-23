defmodule Bbh.Repo.Migrations.AddTesterToPushSubscriptions do
  use Ecto.Migration

  # Marks a device as a test receiver: an admin can target "Nur Testgeräte" from
  # /admin/push to try a message before it reaches every subscriber. Only set via
  # the authenticated admin route, never from the public subscribe API.
  def change do
    alter table(:push_subscriptions) do
      add :tester, :boolean, null: false, default: false
    end
  end
end
