defmodule Bbh.Content.TagsTest do
  use Bbh.DataCase, async: true

  import Bbh.ContentFixtures

  alias Bbh.Content
  alias Bbh.Content.Article

  defp tags(article), do: Repo.reload!(article).tags

  describe "normalize_tags/1" do
    test "splits on commas, trims, drops blanks and case repeats" do
      assert Article.normalize_tags([" Biwak, Corona", "", "biwak", "Thron "]) ==
               ["Biwak", "Corona", "Thron"]
    end
  end

  describe "writing an article" do
    test "a known tag keeps the spelling already in use" do
      article_fixture(tags: ["Thron"])
      article = article_fixture(tags: ["thron", "Neu"])

      assert tags(article) == ["Thron", "Neu"]
    end

    test "fixing the spelling on a tag's only article sticks" do
      article = article_fixture(tags: ["jugend"])
      {:ok, _} = Content.update_article(article, %{tags: ["Jugend"]})

      assert tags(article) == ["Jugend"]
    end
  end

  describe "list_tags/0 and tag_names/1" do
    test "counts articles per tag, drafts included, A–Z" do
      article_fixture(tags: ["Thron", "biwak"])
      article_fixture(tags: ["Thron"], status: "draft")

      assert Content.Tags.list_tags() == [%{name: "biwak", count: 1}, %{name: "Thron", count: 2}]
    end

    test "tag_names/1 leaves out tags only the given article carries" do
      article_fixture(tags: ["Thron"])
      article = article_fixture(tags: ["Thron", "Einzeln"])

      assert Content.Tags.tag_names() == ["Einzeln", "Thron"]
      assert Content.Tags.tag_names(article.id) == ["Thron"]
    end
  end

  describe "rename_tag/2" do
    test "renames on every article and merges into an existing tag" do
      a = article_fixture(tags: ["JHV", "Jahreshauptversammlung"])
      b = article_fixture(tags: ["Biwak", "JHV"])
      c = article_fixture(tags: ["Jahreshauptversammlung"])

      assert {:ok, 2} = Content.Tags.rename_tag("JHV", "jahreshauptversammlung")

      assert tags(a) == ["Jahreshauptversammlung"]
      assert tags(b) == ["Biwak", "Jahreshauptversammlung"]
      assert tags(c) == ["Jahreshauptversammlung"]
    end

    test "fixes the case of a tag" do
      a = article_fixture(tags: ["thron"])
      assert {:ok, 1} = Content.Tags.rename_tag("thron", "Thron")
      assert tags(a) == ["Thron"]
    end

    test "leaves „Geändert am“ alone" do
      a = article_fixture(tags: ["Tipfehler"])
      before = Repo.reload!(a).date_modified

      {:ok, 1} = Content.Tags.rename_tag("Tipfehler", "Tippfehler")
      assert Repo.reload!(a).date_modified == before
    end

    test "refuses a blank name or several tags" do
      article_fixture(tags: ["Thron"])
      assert {:error, _} = Content.Tags.rename_tag("Thron", "  ")
      assert {:error, _} = Content.Tags.rename_tag("Thron", "Thron, Kaiser")
    end
  end

  describe "delete_tag/2" do
    test "is admin-only" do
      a = article_fixture(tags: ["Corona"])
      editor = Bbh.Accounts.Scope.for_user(Bbh.AccountsFixtures.user_fixture())

      assert {:error, :unauthorized} = Content.Tags.delete_tag(editor, "Corona")
      assert tags(a) == ["Corona"]
    end

    test "removes the tag from every article" do
      a = article_fixture(tags: ["Corona", "Biwak"])
      b = article_fixture(tags: ["Corona"])
      admin = Bbh.Accounts.Scope.for_user(Bbh.AccountsFixtures.admin_user_fixture())

      assert {:ok, 2} = Content.Tags.delete_tag(admin, "Corona")
      assert tags(a) == ["Biwak"]
      assert tags(b) == []
    end
  end
end
