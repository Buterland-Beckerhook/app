defmodule Bbh.Repo.Migrations.FixThroneArticleFkCascade do
  use Ecto.Migration

  # The original create migration was later edited to `on_delete: :delete_all`,
  # but dev databases created before that edit still carry the old SET NULL rule.
  # SET NULL on a NOT NULL `article_id` makes deleting an article crash, so this
  # migration realigns the constraint with the intended cascade behaviour.
  def up do
    drop constraint(:thrones, "thrones_article_id_fkey")

    alter table(:thrones) do
      modify :article_id,
             references(:articles, type: :binary_id, on_delete: :delete_all),
             null: false
    end
  end

  def down do
    drop constraint(:thrones, "thrones_article_id_fkey")

    alter table(:thrones) do
      modify :article_id,
             references(:articles, type: :binary_id, on_delete: :nilify_all),
             null: false
    end
  end
end
