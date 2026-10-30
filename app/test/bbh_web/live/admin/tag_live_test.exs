defmodule BbhWeb.Admin.TagLiveTest do
  use BbhWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import Bbh.ContentFixtures

  describe "as admin" do
    setup :register_and_log_in_admin

    test "lists tags with counts and flags case variants", %{conn: conn} do
      article_fixture(tags: ["Thron", "Biwak"])
      # Writes take the spelling in use, so a case variant is old data only.
      article_fixture() |> Ecto.Changeset.change(tags: ["thron"]) |> Bbh.Repo.update!()

      {:ok, _lv, html} = live(conn, ~p"/admin/schlagworte")

      assert html =~ "Biwak"
      assert html =~ "Schreibweise doppelt"
    end

    test "renames a tag on every article", %{conn: conn} do
      a = article_fixture(tags: ["JHV"])
      {:ok, lv, _html} = live(conn, ~p"/admin/schlagworte")

      lv |> element("a[aria-label='„JHV“ umbenennen']") |> render_click()

      html =
        lv
        |> form("#rename-form", %{new: "Jahreshauptversammlung"})
        |> render_submit()

      assert html =~ "umbenannt (1 Artikel)"
      assert Bbh.Repo.reload!(a).tags == ["Jahreshauptversammlung"]
    end

    test "removes a tag from every article", %{conn: conn} do
      a = article_fixture(tags: ["Corona", "Biwak"])
      {:ok, lv, _html} = live(conn, ~p"/admin/schlagworte")

      lv |> element("a[aria-label='„Corona“ aus allen Artikeln entfernen']") |> render_click()

      assert Bbh.Repo.reload!(a).tags == ["Biwak"]
    end
  end

  describe "as editor" do
    setup :register_and_log_in_user

    test "may rename but not remove", %{conn: conn} do
      article_fixture(tags: ["Corona"])
      {:ok, lv, _html} = live(conn, ~p"/admin/schlagworte")

      assert has_element?(lv, "a[aria-label='„Corona“ umbenennen']")
      refute has_element?(lv, "a[aria-label='„Corona“ aus allen Artikeln entfernen']")

      render_hook(lv, "delete", %{"tag" => "Corona"})
      assert Bbh.Content.Tags.list_tags() == [%{name: "Corona", count: 1}]
    end
  end
end
