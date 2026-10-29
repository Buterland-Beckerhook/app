defmodule Bbh.Repo.Migrations.CreateQueueGrantsAndTicketsRole do
  use Ecto.Migration

  # Who works which Postfach queue (Bbh.Tickets.Grants), plus the role "tickets"
  # ("Nur Postfach") for board members who handle requests but don't edit content.
  # queue_key is a plain string on purpose: fixed code queues today, admin-defined
  # groups later, one column for both.
  def up do
    create table(:queue_grants, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :user_id, references(:users, type: :binary_id, on_delete: :delete_all), null: false
      add :queue_key, :string, null: false
      add :granted_by_id, references(:users, type: :binary_id, on_delete: :nilify_all)
      timestamps(type: :utc_datetime, updated_at: false)
    end

    create unique_index(:queue_grants, [:user_id, :queue_key])
    create index(:queue_grants, [:queue_key])

    drop constraint(:users, :users_role_valid)

    create constraint(:users, :users_role_valid,
             check: "role IN ('admin', 'editor', 'calendar_editor', 'tickets')"
           )
  end

  def down do
    execute "UPDATE users SET role = 'editor' WHERE role = 'tickets'"
    drop constraint(:users, :users_role_valid)

    create constraint(:users, :users_role_valid,
             check: "role IN ('admin', 'editor', 'calendar_editor')"
           )

    drop table(:queue_grants)
  end
end
