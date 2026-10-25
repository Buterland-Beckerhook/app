defmodule Bbh.ClubFixtures do
  @moduledoc "Test helpers for creating people (board members / officers)."

  alias Bbh.Club

  def person_fixture(attrs \\ %{}) do
    attrs =
      Enum.into(attrs, %{
        name: "Max Mustermann",
        role: "vorstand"
      })

    {:ok, person} = Club.create_person(attrs)
    person
  end

  def trophy_fixture(attrs \\ %{}) do
    {:ok, trophy} =
      attrs
      |> Enum.into(%{name: "Pokal #{System.unique_integer([:positive])}"})
      |> Club.create_trophy()

    trophy
  end

  def trophy_win_fixture(attrs \\ %{}) do
    attrs = Map.new(attrs)
    trophy = Map.get_lazy(attrs, :trophy, &trophy_fixture/0)

    {:ok, win} =
      attrs
      |> Map.delete(:trophy)
      |> Enum.into(%{trophy_id: trophy.id, year: 2024, winner: "Max Mustermann"})
      |> Club.create_trophy_win()

    win
  end
end
