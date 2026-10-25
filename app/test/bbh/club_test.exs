defmodule Bbh.ClubTest do
  use Bbh.DataCase, async: true

  alias Bbh.Club
  alias Bbh.Club.Person

  import Bbh.ClubFixtures
  import Bbh.ContentFixtures, only: [upload_fixture: 1]

  describe "list_people/2" do
    test "filters by the given roles" do
      praesident = person_fixture(role: "praesident")
      _offizier = person_fixture(role: "offizier")

      people = Club.list_people(["praesident"])
      assert Enum.map(people, & &1.id) == [praesident.id]
    end

    test "an empty role list means every role" do
      praesident = person_fixture(role: "praesident")
      offizier = person_fixture(role: "offizier")

      ids = Club.list_people([]) |> Enum.map(& &1.id) |> Enum.sort()
      assert ids == Enum.sort([praesident.id, offizier.id])
    end

    test "an appointment year makes an honorary member" do
      honorary = person_fixture(role: "vorstand", honorary_since: 2018)
      regular = person_fixture(role: "vorstand", honorary_since: nil)

      assert Club.list_people(["vorstand"], honorary: "only") |> Enum.map(& &1.id) == [
               honorary.id
             ]

      assert Club.list_people(["vorstand"], honorary: "exclude") |> Enum.map(& &1.id) == [
               regular.id
             ]

      all_ids =
        Club.list_people(["vorstand"], honorary: "all") |> Enum.map(& &1.id) |> Enum.sort()

      assert all_ids == Enum.sort([honorary.id, regular.id])
    end

    test "only_active keeps the people without an „Amt bis\"" do
      serving = person_fixture(role: "vorstand", name: "Amtierend", year_end: nil)
      _former = person_fixture(role: "vorstand", name: "Ehemalig", year_end: 1998)

      assert Club.list_people(["vorstand"], only_active: true) |> Enum.map(& &1.id) == [
               serving.id
             ]

      # Off (the default) everyone comes back.
      assert Club.list_people(["vorstand"]) |> length() == 2
    end

    test "only_active composes with the role and honorary filters" do
      serving = person_fixture(role: "vorstand", name: "A", year_end: nil, honorary_since: nil)
      _serving_honorary = person_fixture(role: "vorstand", name: "B", honorary_since: 2021)
      _former = person_fixture(role: "vorstand", name: "C", year_end: 1998)
      _other_role = person_fixture(role: "oberst", name: "D", year_end: nil)

      ids =
        Club.list_people(["vorstand"], honorary: "exclude", only_active: true)
        |> Enum.map(& &1.id)

      assert ids == [serving.id]
    end

    test "the unknown-year placeholder still counts as honorary" do
      unknown = person_fixture(role: "mitglied", honorary_since: Person.unknown_honorary_year())

      assert Club.list_people([], honorary: "only") |> Enum.map(& &1.id) == [unknown.id]
    end

    test "alive splits on the death date" do
      living = person_fixture(role: "mitglied", name: "Lebt")
      dead = person_fixture(role: "mitglied", name: "Tot", death_date: ~D[2019-10-25])

      assert Club.list_people([], alive: "living") |> Enum.map(& &1.id) == [living.id]
      assert Club.list_people([], alive: "deceased") |> Enum.map(& &1.id) == [dead.id]
      assert Club.list_people([], alive: "all") |> length() == 2
    end

    test "sort: honorary_since orders by appointment, oldest first, placeholder before" do
      late = person_fixture(role: "mitglied", name: "Spät", honorary_since: 2024)
      early = person_fixture(role: "mitglied", name: "Früh", honorary_since: 1978)
      unknown = person_fixture(role: "mitglied", name: "Unbekannt", honorary_since: 1900)

      assert Club.list_people([], honorary: "only", sort: "honorary_since")
             |> Enum.map(& &1.id) == [unknown.id, early.id, late.id]
    end

    test "rejects an appointment year before the placeholder" do
      assert {:error, changeset} =
               Club.create_person(%{name: "X", role: "mitglied", honorary_since: 1899})

      assert %{honorary_since: [_]} = errors_on(changeset)
    end

    test "sorts by sort_order then name by default" do
      c = person_fixture(role: "vorstand", name: "Cäsar", sort_order: 0)
      a = person_fixture(role: "vorstand", name: "Anton", sort_order: 1)
      b = person_fixture(role: "vorstand", name: "Berta", sort_order: 0)

      # sort_order first (0 before 1), name breaks the tie within the same sort_order.
      assert Club.list_people(["vorstand"]) |> Enum.map(& &1.id) == [b.id, c.id, a.id]
    end

    test "sort: year_start orders by Amtsantritt, oldest first, missing last" do
      old = person_fixture(role: "vorstand", name: "Alt", year_start: 1990)
      new = person_fixture(role: "vorstand", name: "Neu", year_start: 2020)
      none = person_fixture(role: "vorstand", name: "Ohne", year_start: nil)

      assert Club.list_people(["vorstand"], sort: "year_start") |> Enum.map(& &1.id) ==
               [old.id, new.id, none.id]
    end

    test "preloads the portrait" do
      upload = upload_fixture(filename: "portrait.webp")
      person_fixture(role: "vorstand", portrait_id: upload.id)

      [person] = Club.list_people(["vorstand"])
      assert person.portrait.id == upload.id
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

  describe "get_person!/1" do
    test "preloads the portrait so the admin form can show its thumbnail" do
      upload = upload_fixture(filename: "portrait.webp")
      person = person_fixture(role: "vorstand", portrait_id: upload.id)

      assert Club.get_person!(person.id).portrait.id == upload.id
    end
  end

  describe "change_person/2" do
    test "sanitizes the biography, which is rendered as raw HTML on the public site" do
      changeset =
        Club.change_person(%Bbh.Club.Person{}, %{
          "name" => "Heinrich Meyer",
          "role" => "vorstand",
          "biography" => "<p>Hallo</p><script>alert(1)</script>"
        })

      biography = Ecto.Changeset.get_change(changeset, :biography)
      assert biography =~ "<p>Hallo</p>"
      refute biography =~ "script"
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
