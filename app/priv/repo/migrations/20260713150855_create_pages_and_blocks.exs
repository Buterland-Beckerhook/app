defmodule Bbh.Repo.Migrations.CreatePagesAndBlocks do
  use Ecto.Migration

  def change do
    create table(:pages, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :status, :string, null: false, default: "draft"
      add :title, :string, null: false
      add :slug, :string, null: false
      add :parent_id, references(:pages, type: :binary_id, on_delete: :nilify_all)
      add :sort_order, :integer, null: false, default: 0

      timestamps(type: :utc_datetime)
    end

    create unique_index(:pages, [:slug])
    create index(:pages, [:status, :slug])

    create table(:block_richtext, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :body, :text, null: false
      timestamps(type: :utc_datetime)
    end

    create table(:block_alert, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :icon, :string, null: false, default: "info"
      add :body, :text, null: false
      timestamps(type: :utc_datetime)
    end

    create table(:block_media_card, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :title, :string
      add :subtitle, :string
      add :body, :text
      add :image_position, :string, null: false, default: "right"
      add :image_id, references(:media, type: :binary_id, on_delete: :nilify_all)
      timestamps(type: :utc_datetime)
    end

    create table(:block_image_gallery, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :title, :string
      add :layout, :string, null: false, default: "slideshow"
      add :lightbox, :boolean, null: false, default: true
      timestamps(type: :utc_datetime)
    end

    create table(:block_gallery_files, primary_key: false) do
      add :id, :binary_id, primary_key: true

      add :gallery_id, references(:block_image_gallery, type: :binary_id, on_delete: :delete_all),
        null: false

      add :media_id, references(:media, type: :binary_id, on_delete: :delete_all), null: false
      add :title, :string
      add :copyright, :string
      add :sort, :integer
      timestamps(type: :utc_datetime)
    end

    create index(:block_gallery_files, [:gallery_id])
    create index(:block_gallery_files, [:media_id])
    create index(:block_media_card, [:image_id])

    create table(:block_person_list, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :title, :string
      add :filter_roles, {:array, :string}, null: false, default: []
      add :filter_honorary, :string, null: false, default: "all"
      add :display_style, :string, null: false, default: "table"
      add :show_address, :boolean, null: false, default: false
      timestamps(type: :utc_datetime)
    end

    # Ordered polymorphic join (the Directus M2A). block_id points at whichever
    # block_* table `block_type` names; integrity is enforced in the app layer.
    create table(:page_blocks, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :page_id, references(:pages, type: :binary_id, on_delete: :delete_all), null: false
      add :position, :integer, null: false, default: 0
      add :block_type, :string, null: false
      add :block_id, :binary_id, null: false

      timestamps(type: :utc_datetime)
    end

    create index(:page_blocks, [:page_id, :position])
  end
end
