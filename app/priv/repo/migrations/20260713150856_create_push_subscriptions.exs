defmodule Bbh.Repo.Migrations.CreatePushSubscriptions do
  use Ecto.Migration

  def change do
    create table(:push_subscriptions, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :endpoint, :text, null: false
      add :keys_p256dh, :string, null: false
      add :keys_auth, :string, null: false
      add :categories, {:array, :string}, null: false, default: []
      add :last_used, :utc_datetime

      timestamps(type: :utc_datetime)
    end

    create unique_index(:push_subscriptions, [:endpoint])
  end
end
