defmodule Bbh.ClubTest do
  use Bbh.DataCase, async: true

  alias Bbh.Club

  import Bbh.ClubFixtures

  describe "list_people/2" do
    test "filters by the given roles" do
      praesident = person_fixture(role: "praesident")
      _offizier = person_fixture(role: "offizier")

      people = Club.list_people(["praesident"])
      assert Enum.map(people, & &1.id) == [praesident.id]
    end

    test "honorary flag filters honorary members" do
      honorary = person_fixture(role: "vorstand", honorary_member: true)
      regular = person_fixture(role: "vorstand", honorary_member: false)

      assert Club.list_people(["vorstand"], "only") |> Enum.map(& &1.id) == [honorary.id]
      assert Club.list_people(["vorstand"], "exclude") |> Enum.map(& &1.id) == [regular.id]

      all_ids = Club.list_people(["vorstand"], "all") |> Enum.map(& &1.id) |> Enum.sort()
      assert all_ids == Enum.sort([honorary.id, regular.id])
    end
  end

  describe "list_vorstand/0 and list_offiziere/0" do
    test "return the correct role subsets" do
      praesident = person_fixture(role: "praesident")
      oberst = person_fixture(role: "oberst")

      vorstand_ids = Club.list_vorstand() |> Enum.map(& &1.id)
      offizier_ids = Club.list_offiziere() |> Enum.map(& &1.id)

      assert praesident.id in vorstand_ids
      refute oberst.id in vorstand_ids

      assert oberst.id in offizier_ids
      refute praesident.id in offizier_ids
    end
  end

  describe "role_options/0" do
    test "returns {label, role} tuples for all roles" do
      options = Club.role_options()
      assert {"Präsident", "praesident"} in options
      assert length(options) == length(Bbh.Club.Person.roles())
    end
  end
end
