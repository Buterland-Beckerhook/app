defmodule Bbh.Content.Throne do
  @moduledoc "König/Kaiser record. `begin_year`/`end_year` map to the `begin`/`end` columns."
  use Bbh.Schema

  @types ~w(koenig kaiser stadtkaiser)
  def types, do: @types

  schema "thrones" do
    field :type, :string
    field :begin_year, :integer, source: :begin
    field :end_year, :integer, source: :end
    field :king_title, :string
    field :king, :string
    field :queen, :string
    field :moh1, :string
    field :moh2, :string
    field :loh1, :string
    field :loh2, :string
    field :cupbearer, :string
    field :courtmarshal, :string

    belongs_to :article, Bbh.Content.Article

    timestamps()
  end

  @doc false
  def changeset(throne, attrs) do
    throne
    |> cast(attrs, [
      :type,
      :begin_year,
      :end_year,
      :king_title,
      :king,
      :queen,
      :moh1,
      :moh2,
      :loh1,
      :loh2,
      :cupbearer,
      :courtmarshal,
      :article_id
    ])
    |> validate_required([:type, :begin_year, :king, :queen, :article_id])
    |> validate_inclusion(:type, @types)
    |> validate_number(:begin_year, greater_than: 0)
    |> validate_end_after_begin()
    |> unique_constraint(:article_id)
    |> foreign_key_constraint(:article_id)
    |> check_constraint(:end_year,
      name: :thrones_end_after_begin,
      message: "muss nach dem Beginn liegen"
    )
  end

  defp validate_end_after_begin(changeset) do
    b = get_field(changeset, :begin_year)
    e = get_field(changeset, :end_year)

    if b && e && e < b do
      add_error(changeset, :end_year, "muss nach dem Beginn liegen")
    else
      changeset
    end
  end
end
