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
end
