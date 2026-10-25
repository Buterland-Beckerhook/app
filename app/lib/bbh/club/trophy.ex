defmodule Bbh.Club.Trophy do
  @moduledoc "A Pokal shot for every year (Schützenpokal, Königspokal, …)."
  use Bbh.Schema

  schema "trophies" do
    field :name, :string
    # Year the trophy was first shot for, as the club tells it („seit 1965").
    field :since, :integer
    # Who may shoot and where it came from; plain text, shown under the Pokalsieger table.
    field :description, :string
    field :sort_order, :integer, default: 0

    has_many :wins, Bbh.Club.TrophyWin

    timestamps()
  end

  @doc false
  def changeset(trophy, attrs) do
    trophy
    |> cast(attrs, [:name, :since, :description, :sort_order])
    |> validate_required([:name])
    |> validate_number(:since, greater_than_or_equal_to: 1900)
    |> validate_number(:sort_order, greater_than_or_equal_to: 0)
    |> unique_constraint(:name, message: "gibt es schon")
  end
end
