defmodule BbhWeb.AuthzTest do
  use ExUnit.Case, async: true

  alias Bbh.Accounts.User
  alias Bbh.Calendar.Event
  alias BbhWeb.Authz

  defp admin, do: %User{role: "admin", calendars: []}
  defp editor(cals \\ []), do: %User{role: "editor", calendars: cals}
  defp cal_editor(cals), do: %User{role: "calendar_editor", calendars: cals}

  defp public_event, do: %Event{calendar: nil}
  defp event(cal), do: %Event{calendar: cal}

  describe "can_access_section?/2" do
    test "admin reaches every section" do
      for s <- [:dashboard, :events, :articles, :people, :pages, :media, :users] do
        assert Authz.can_access_section?(admin(), s)
      end
    end

    test "editor reaches content + events but not users" do
      assert Authz.can_access_section?(editor(), :articles)
      assert Authz.can_access_section?(editor(), :events)
      refute Authz.can_access_section?(editor(), :users)
    end

    test "calendar editor reaches only events + dashboard" do
      assert Authz.can_access_section?(cal_editor(["vorstand"]), :events)
      assert Authz.can_access_section?(cal_editor(["vorstand"]), :dashboard)
      refute Authz.can_access_section?(cal_editor(["vorstand"]), :articles)
      refute Authz.can_access_section?(cal_editor(["vorstand"]), :users)
    end
  end

  describe "can_manage_calendar?/2" do
    test "admin manages every calendar including public" do
      assert Authz.can_manage_calendar?(admin(), nil)
      assert Authz.can_manage_calendar?(admin(), "vorstand")
    end

    test "editor manages public but not private unless granted" do
      assert Authz.can_manage_calendar?(editor(), nil)
      refute Authz.can_manage_calendar?(editor(), "vorstand")
      assert Authz.can_manage_calendar?(editor(["vorstand"]), "vorstand")
    end

    test "calendar editor manages only granted calendars, not public" do
      refute Authz.can_manage_calendar?(cal_editor(["vorstand"]), nil)
      assert Authz.can_manage_calendar?(cal_editor(["vorstand"]), "vorstand")
      refute Authz.can_manage_calendar?(cal_editor(["vorstand"]), "offiziere")
    end
  end

  describe "can_delete_event?/2" do
    test "public events are admin-only" do
      assert Authz.can_delete_event?(admin(), public_event())
      refute Authz.can_delete_event?(editor(), public_event())
    end

    test "granted non-public calendars can be deleted by the grantee" do
      assert Authz.can_delete_event?(cal_editor(["vorstand"]), event("vorstand"))
      refute Authz.can_delete_event?(cal_editor(["vorstand"]), event("offiziere"))
      assert Authz.can_delete_event?(editor(["vorstand"]), event("vorstand"))
    end
  end

  describe "can_delete?/2 (non-event resources)" do
    test "only admins may delete" do
      assert Authz.can_delete?(admin(), :anything)
      refute Authz.can_delete?(editor(), :anything)
      refute Authz.can_delete?(cal_editor(["vorstand"]), :anything)
    end
  end

  describe "assignable_calendar_options/1" do
    test "admin gets public plus every calendar" do
      values = admin() |> Authz.assignable_calendar_options() |> Enum.map(&elem(&1, 1))
      assert "" in values
      assert Enum.all?(Event.calendars(), &(&1 in values))
    end

    test "calendar editor gets only granted calendars, no public" do
      values =
        ["vorstand"]
        |> cal_editor()
        |> Authz.assignable_calendar_options()
        |> Enum.map(&elem(&1, 1))

      assert values == ["vorstand"]
    end
  end
end
