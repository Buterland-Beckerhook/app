defmodule Bbh.Repo.Migrations.CreateBlockEvent do
  use Ecto.Migration

  # A content block that shows one event — typically the Schützenfest with its programme
  # in the invitation article. It stores only *which* event and how to show it; the
  # event and its programme are read live at render time, so a later change to a time or
  # a cancellation reaches the article without editing it. Deleting the event leaves an
  # empty block behind (it renders nothing) rather than deleting article content.
  def change do
    create table(:block_event, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :event_id, references(:events, type: :binary_id, on_delete: :nilify_all)
      add :show_header, :boolean, null: false, default: true
      add :show_body, :boolean, null: false, default: false
      add :show_programme, :boolean, null: false, default: true
      timestamps(type: :utc_datetime)
    end

    create index(:block_event, [:event_id])
  end
end
