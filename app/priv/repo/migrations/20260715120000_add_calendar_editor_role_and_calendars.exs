defmodule Bbh.Repo.Migrations.AddCalendarEditorRoleAndCalendars do
  use Ecto.Migration

  def up do
    alter table(:users) do
      add :calendars, {:array, :string}, null: false, default: []
    end

    drop constraint(:users, :users_role_valid)

    create constraint(:users, :users_role_valid,
             check: "role IN ('admin', 'editor', 'calendar_editor')"
           )
  end

  def down do
    # Demote any calendar editors before tightening the constraint again.
    execute "UPDATE users SET role = 'editor' WHERE role = 'calendar_editor'"

    drop constraint(:users, :users_role_valid)

    create constraint(:users, :users_role_valid, check: "role IN ('admin', 'editor')")

    alter table(:users) do
      remove :calendars
    end
  end
end
