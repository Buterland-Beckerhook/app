defmodule Bbh.Content.Thrones do
  @moduledoc """
  The throne records (König, Kaiser, Stadtkaiser, Jungschützenkönig): the reigning ones
  for the homepage, the /thron gallery and its navigation, and editing a throne in the
  context of its article.
  """
  import Ecto.Query
  alias Bbh.{Content, Repo}
  alias Bbh.Content.Throne

  @doc "The currently reigning throne (latest by begin year), with its article + image."
  def current_throne do
    Repo.one(
      from t in Throne,
        order_by: [desc: t.begin_year],
        limit: 1,
        preload: [:image, article: :image]
    )
  end

  @doc """
  The currently reigning throne of each type for the homepage throne section, ordered
  König → Kaiser → Stadtkaiser → Jungschützenkönig. Missing types are omitted.

  König and Jungschützenkönig change yearly, so we take the most recent one. A
  Kaiser/Stadtkaiser reigns until the next Kaiserthron/Stadtschützenfest — which the club
  does not hold every year and may postpone — so the current one is the latest with an
  *open* end year; once it has concluded and no successor exists, none is shown.
  """
  def current_thrones do
    [
      current_throne_of_type("koenig"),
      current_open_throne_of_type("kaiser"),
      current_open_throne_of_type("stadtkaiser"),
      current_throne_of_type("jungschuetzenkoenig")
    ]
    |> Enum.reject(&is_nil/1)
  end

  defp current_throne_of_type(type) do
    Repo.one(
      from t in Throne,
        where: t.type == ^type,
        order_by: [desc: t.begin_year],
        limit: 1,
        preload: [:image, article: :image]
    )
  end

  # Latest still-reigning throne of a type (no end year set yet).
  defp current_open_throne_of_type(type) do
    Repo.one(
      from t in Throne,
        where: t.type == ^type and is_nil(t.end_year),
        order_by: [desc: t.begin_year],
        limit: 1,
        preload: [:image, article: :image]
    )
  end

  @doc "Thrones of one type, newest first, paginated (the /thron gallery), with article + image."
  def list_thrones(type, page \\ 1, per_page \\ 1) do
    base = from t in Throne, where: t.type == ^type, order_by: [desc: t.begin_year]
    Content.paginate(base, page, per_page, preload: [:image, article: :image])
  end

  @doc """
  The throne of `type` that began in `begin_year`, with article + image, or nil. Backs
  the stable `/thron?jahr=` URLs. Should a year ever hold two thrones of one type, the
  first-entered one wins, so the result stays deterministic.
  """
  def get_throne_by_year(type, begin_year) do
    Repo.one(
      from t in Throne,
        where: t.type == ^type and t.begin_year == ^begin_year,
        order_by: [asc: t.inserted_at, asc: t.id],
        limit: 1,
        preload: [:image, article: :image]
    )
  end

  @doc "Schlanke Liste der Throne eines Typs (neueste zuerst) für den /thron-Pager."
  def list_throne_nav(type) do
    Repo.all(
      from t in Throne,
        where: t.type == ^type,
        order_by: [desc: t.begin_year],
        select: %{begin_year: t.begin_year, end_year: t.end_year, king: t.king, type: t.type}
    )
  end

  @doc """
  Data for the Thron dropdown menu: the Kaiser reigns (newest first, with their linked
  article for direct links) and the set of throne types that have at least one record.
  """
  def throne_menu do
    kaiser =
      Repo.all(
        from t in Throne,
          where: t.type == "kaiser",
          order_by: [desc: t.begin_year],
          preload: [:article]
      )

    types = Repo.all(from t in Throne, distinct: true, select: t.type) |> MapSet.new()

    %{kaiser: kaiser, types_present: types}
  end

  def create_throne(attrs),
    do: %Throne{} |> Throne.changeset(attrs) |> Repo.insert() |> Bbh.Search.reindex_after()

  def update_throne(%Throne{} = t, attrs),
    do: t |> Throne.changeset(attrs) |> Repo.update() |> Bbh.Search.reindex_after()

  def delete_throne(%Throne{} = t), do: t |> Repo.delete() |> Bbh.Search.reindex_after()
  def change_throne(%Throne{} = t, attrs \\ %{}), do: Throne.changeset(t, attrs)

  @doc "Set (or clear with `nil`) a throne's own picture. `nil` inherits the article image."
  def set_throne_image(%Throne{} = throne, media_id) do
    # force_change so a clear (nil) always writes even when the passed struct is stale —
    # see set_article_image/2.
    throne
    |> Throne.changeset(%{})
    |> Ecto.Changeset.force_change(:image_id, media_id)
    |> Repo.update()
    |> Bbh.Search.reindex_after()
  end
end
