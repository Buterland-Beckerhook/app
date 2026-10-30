defmodule Bbh.ClubTrophiesTest do
  use Bbh.DataCase, async: true

  import Bbh.ClubFixtures

  alias Bbh.Accounts.Scope
  alias Bbh.Club

  defp admin_scope, do: Scope.for_user(Bbh.AccountsFixtures.admin_user_fixture())

  describe "trophy wins" do
    test "one winner per trophy and year" do
      trophy = trophy_fixture()
      trophy_win_fixture(trophy: trophy, year: 2024)

      assert {:error, changeset} =
               Club.create_trophy_win(%{trophy_id: trophy.id, year: 2024, winner: "Zweiter"})

      assert %{year: ["für diesen Pokal ist schon ein Sieger eingetragen"]} = errors_on(changeset)
    end

    test "rings must be positive, the year a real one" do
      trophy = trophy_fixture()

      assert {:error, changeset} =
               Club.create_trophy_win(%{trophy_id: trophy.id, year: 1850, winner: "X", rings: 0})

      assert %{year: [_], rings: [_]} = errors_on(changeset)
    end

    test "a trophy with winners is not deleted" do
      trophy = trophy_fixture()
      trophy_win_fixture(trophy: trophy)

      assert {:error, :has_wins} = Club.delete_trophy(admin_scope(), trophy)
      assert Club.get_trophy!(trophy.id)
    end

    test "a trophy without winners is deleted" do
      trophy = trophy_fixture()
      assert {:ok, _} = Club.delete_trophy(admin_scope(), trophy)
    end

    test "deletes are admin-only" do
      trophy = trophy_fixture()
      win = trophy_win_fixture(trophy: trophy)
      editor = Scope.for_user(Bbh.AccountsFixtures.user_fixture())

      assert {:error, :unauthorized} = Club.delete_trophy_win(editor, win)
      assert {:error, :unauthorized} = Club.delete_trophy(editor, trophy)
      assert {:error, :unauthorized} = Club.delete_trophy_win(nil, win)
      assert {:ok, _} = Club.delete_trophy_win(admin_scope(), win)
    end
  end

  describe "trophy_table/0" do
    test "is empty without winners" do
      trophy_fixture()
      assert %{rows: []} = Club.trophy_table()
    end

    test "has a row for every year from the newest to the oldest, gaps included" do
      a = trophy_fixture(name: "A", sort_order: 1)
      b = trophy_fixture(name: "B", sort_order: 2)
      trophy_win_fixture(trophy: a, year: 2026, winner: "Neu")
      trophy_win_fixture(trophy: b, year: 2023, winner: "Alt")

      %{trophies: trophies, rows: rows} = Club.trophy_table()

      assert Enum.map(trophies, & &1.name) == ["A", "B"]
      assert Enum.map(rows, &elem(&1, 0)) == [2026, 2025, 2024, 2023]
      assert {2026, %{} = wins} = hd(rows)
      assert wins[a.id].winner == "Neu"
      assert wins[b.id] == nil
      assert {2025, empty} = Enum.at(rows, 1)
      assert empty == %{}
    end
  end

  describe "trophy_records/1" do
    test "names whoever won a trophy most often, ties included, from the minimum on" do
      t = trophy_fixture(name: "Schützenpokal")
      other = trophy_fixture(name: "Selten")

      for y <- [2001, 2002, 2003], do: trophy_win_fixture(trophy: t, year: y, winner: "Anna")
      for y <- [2004, 2005, 2006], do: trophy_win_fixture(trophy: t, year: y, winner: "Bernd")
      trophy_win_fixture(trophy: t, year: 2007, winner: "Carl")
      trophy_win_fixture(trophy: other, year: 2001, winner: "Dora")

      assert [{%{name: "Schützenpokal"}, 3, ["Anna", "Bernd"]}] = Club.trophy_records()
      assert [_, {%{name: "Selten"}, 1, ["Dora"]}] = Club.trophy_records(1)
    end
  end
end
