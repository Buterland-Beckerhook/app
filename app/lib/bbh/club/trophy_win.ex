defmodule Bbh.Club.TrophyWin do
  @moduledoc """
  Who won a trophy in a year. The winner is a plain name, as on `thrones`: most winners
  hold no office, so there is no `people` row to point at.
  """
  use Bbh.Schema

  schema "trophy_wins" do
    field :year, :integer
    field :winner, :string
    # Not every report names them; the shooting is out of 30.
    field :rings, :integer
    field :note, :string

    belongs_to :trophy, Bbh.Club.Trophy

    timestamps()
  end

  @doc false
  def changeset(win, attrs) do
    win
    |> cast(attrs, [:trophy_id, :year, :winner, :rings, :note])
    |> update_change(:winner, &String.trim/1)
    |> validate_required([:trophy_id, :year, :winner])
    |> validate_number(:year, greater_than_or_equal_to: 1900)
    |> validate_number(:rings, greater_than: 0)
    |> foreign_key_constraint(:trophy_id)
    |> unique_constraint([:trophy_id, :year],
      error_key: :year,
      message: "für diesen Pokal ist schon ein Sieger eingetragen"
    )
    |> check_constraint(:year, name: :trophy_wins_year_range, message: "muss ab 1900 liegen")
    |> check_constraint(:rings, name: :trophy_wins_rings_positive, message: "muss positiv sein")
  end
end
