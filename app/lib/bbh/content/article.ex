defmodule Bbh.Content.Article do
  @moduledoc "News/article (Artikel). `year` is derived from `date_published`."
  use Bbh.Schema

  @statuses ~w(draft published archived)
  def statuses, do: @statuses

  schema "articles" do
    field :status, :string, default: "draft"
    field :title, :string
    field :subtitle, :string
    field :slug, :string
    field :date_published, :utc_datetime
    field :date_modified, :utc_datetime
    # Set once the publish push has been sent; guards against re-notifying.
    field :notified_at, :utc_datetime
    field :year, :integer
    field :author, :string
    field :tags, {:array, :string}, default: []
    field :body, :string
    field :no_article, :boolean, default: false
    field :aliases, {:array, :string}, default: []

    # The single, first-class article image (hero + throne default). Assigned from the
    # Mediathek; caption/copyright live on the Upload.
    belongs_to :image, Bbh.Media.Upload

    # Ordered content blocks (mixed text/images/galleries), the article body's new home.
    has_many :article_blocks, Bbh.Content.ArticleBlock, preload_order: [asc: :position]

    # Legacy: kept one release for rollback while `body`/blocks coexist. `images` and
    # `body` are no longer surfaced in the editor; a follow-up migration drops them.
    # `preload_order` so every preload — article page, homepage, /thron, search —
    # honours the editor's sort order instead of returning rows in insert order.
    has_many :images, Bbh.Content.ArticleImage, preload_order: [asc: :sort, asc: :inserted_at]
    has_one :throne, Bbh.Content.Throne

    timestamps()
  end

  @doc false
  def changeset(article, attrs) do
    article
    |> cast(attrs, [
      :status,
      :title,
      :subtitle,
      :slug,
      :date_published,
      :author,
      :tags,
      :body,
      :no_article,
      :aliases,
      :image_id
    ])
    |> update_change(:body, &Bbh.Html.sanitize/1)
    |> validate_required([:status, :title, :slug, :date_published])
    |> validate_inclusion(:status, @statuses)
    |> put_year()
    |> put_date_modified()
    |> validate_number(:year, greater_than_or_equal_to: 1900)
    |> unique_constraint([:slug, :year], name: :articles_slug_year_unique)
    |> foreign_key_constraint(:image_id)
    |> check_constraint(:year,
      name: :articles_year_range,
      message: "muss ab 1900 liegen"
    )
  end

  defp put_year(changeset) do
    case get_field(changeset, :date_published) do
      %DateTime{year: year} -> put_change(changeset, :year, year)
      _ -> changeset
    end
  end

  # Bump "Geändert am" whenever an already-persisted article is actually changed.
  # `date_published` ("Veröffentlicht am") is left untouched — it stays user-owned.
  defp put_date_modified(changeset) do
    if changeset.data.__meta__.state == :loaded and map_size(changeset.changes) > 0 do
      put_change(changeset, :date_modified, Bbh.Time.now())
    else
      changeset
    end
  end
end
