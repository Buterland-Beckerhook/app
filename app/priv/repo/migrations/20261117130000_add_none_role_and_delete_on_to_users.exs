defmodule Bbh.Repo.Migrations.AddNoneRoleAndDeleteOnToUsers do
  use Ecto.Migration

  # Role "none" ("Kein Zugriff") for people who keep their account but no longer hold an
  # office (e.g. after leaving the board), and `delete_on`: the day on which
  # Bbh.Workers.UserDeleter removes the account.
  def up do
    alter table(:users) do
      add :delete_on, :date
    end

    drop constraint(:users, :users_role_valid)

    create constraint(:users, :users_role_valid,
             check: "role IN ('admin', 'editor', 'calendar_editor', 'tickets', 'none')"
           )
  end

  def down do
    # "Nur Postfach" without queue grants is the closest to no access.
    execute "UPDATE users SET role = 'tickets' WHERE role = 'none'"
    drop constraint(:users, :users_role_valid)

    create constraint(:users, :users_role_valid,
             check: "role IN ('admin', 'editor', 'calendar_editor', 'tickets')"
           )

    alter table(:users) do
      remove :delete_on
    end
  end
end
