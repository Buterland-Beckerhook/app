defmodule Bbh.RedirectsTest do
  use Bbh.DataCase, async: true

  alias Bbh.Redirects
  alias Bbh.Redirects.{NotFoundPath, Redirect}

  doctest Bbh.Redirects

  defp redirect_fixture(attrs) do
    {:ok, redirect} = attrs |> Enum.into(%{target: "/aktuell"}) |> Redirects.create_redirect()
    redirect
  end

  describe "normalize_path/1" do
    test "decodes, lowercases and drops query, fragment, repeated and trailing slashes" do
      assert Redirects.normalize_path("/Verein//Vorstand/?a=1#top") == "/verein/vorstand"
      assert Redirects.normalize_path("verein") == "/verein"
      assert Redirects.normalize_path("/") == "/"
    end

    test "keeps an invalid percent-encoding as it is" do
      assert Redirects.normalize_path("/a%ZZb") == "/a%zzb"
      assert Redirects.normalize_path("/a%FFb") == "/a%ffb"
    end
  end

  describe "valid_target?/1" do
    test "accepts site paths and http(s) URLs" do
      assert Redirects.valid_target?("/aktuell")
      assert Redirects.valid_target?("https://example.org/x")
      assert Redirects.valid_target?("http://example.org")
    end

    test "rejects protocol-relative, other schemes and bare words" do
      refute Redirects.valid_target?("//evil.example")
      refute Redirects.valid_target?("javascript:alert(1)")
      refute Redirects.valid_target?("ftp://example.org")
      refute Redirects.valid_target?("aktuell")
      refute Redirects.valid_target?("https://")
    end
  end

  describe "changeset" do
    test "stores the source normalized" do
      redirect = redirect_fixture(source_path: "/Verein/Vorstand/")
      assert redirect.source_path == "/verein/vorstand"
    end

    test "rejects the home page, a catch-all and an inner wildcard" do
      for source <- ["/", "/*", "/a*/b"] do
        changeset = Redirect.changeset(%Redirect{}, %{source_path: source, target: "/x"})
        refute changeset.valid?, "expected #{source} to be rejected"
        assert changeset.errors[:source_path]
      end
    end

    test "rejects a target the rule would catch again" do
      changeset = Redirect.changeset(%Redirect{}, %{source_path: "/a", target: "/A/"})
      assert changeset.errors[:target]

      changeset = Redirect.changeset(%Redirect{}, %{source_path: "/tags/*", target: "/tags/x"})
      assert changeset.errors[:target]

      changeset = Redirect.changeset(%Redirect{}, %{source_path: "/tags/*", target: "/aktuell"})
      assert changeset.valid?
    end

    test "rejects an invalid target" do
      changeset = Redirect.changeset(%Redirect{}, %{source_path: "/a", target: "//evil"})
      assert changeset.errors[:target]
    end

    test "the source is unique" do
      redirect_fixture(source_path: "/a")
      assert {:error, changeset} = Redirects.create_redirect(%{source_path: "/A/", target: "/b"})
      assert changeset.errors[:source_path]
    end
  end

  describe "resolve/1" do
    test "finds an exact rule regardless of case and trailing slash" do
      redirect = redirect_fixture(source_path: "/verein/vorstand/kontakt", target: "/kontakt")

      assert {:rule, %{id: id, target: "/kontakt", permanent: true}} =
               Redirects.resolve("/Verein/Vorstand/Kontakt/")

      assert id == redirect.id
    end

    test "a prefix rule matches its base and everything below it" do
      redirect_fixture(source_path: "/tags/*", target: "/aktuell")

      assert {:rule, %{target: "/aktuell"}} = Redirects.resolve("/tags")
      assert {:rule, %{target: "/aktuell"}} = Redirects.resolve("/tags/a/b")
      assert Redirects.resolve("/tagsx") == nil
    end

    test "exact beats prefix, and the longer prefix wins" do
      redirect_fixture(source_path: "/a/*", target: "/short")
      redirect_fixture(source_path: "/a/b/*", target: "/long")
      redirect_fixture(source_path: "/a/b/c", target: "/exact")

      assert {:rule, %{target: "/exact"}} = Redirects.resolve("/a/b/c")
      assert {:rule, %{target: "/long"}} = Redirects.resolve("/a/b/d")
      assert {:rule, %{target: "/short"}} = Redirects.resolve("/a/x")
    end

    test "nil when nothing applies" do
      assert Redirects.resolve("/gibt/es/nicht") == nil
    end

    test "track_hit/1 counts" do
      redirect = redirect_fixture(source_path: "/a")
      Redirects.track_hit(redirect.id)
      Redirects.track_hit(redirect.id)

      redirect = Redirects.get_redirect!(redirect.id)
      assert redirect.hits == 2
      assert redirect.last_hit_at
    end
  end

  describe "404 log" do
    test "aggregates per normalized path and keeps the external referrer's host + path" do
      Redirects.record_not_found("/Alt/Seite/")
      Redirects.record_not_found("/alt/seite", "https://www.facebook.com/verein/posts/1?fbclid=x")

      assert [%NotFoundPath{path: "/alt/seite", hits: 2, referrer: referrer}] =
               Redirects.list_not_found()

      assert referrer == "www.facebook.com/verein/posts/1"
    end

    test "creating a rule dismisses the entries it covers" do
      Redirects.record_not_found("/tags/schuetzenfest")
      Redirects.record_not_found("/tags")
      Redirects.record_not_found("/tags_x")
      Redirects.record_not_found("/andere")

      redirect_fixture(source_path: "/tags/*", target: "/aktuell")

      assert Enum.map(Redirects.list_not_found(), & &1.path) |> Enum.sort() ==
               ["/andere", "/tags_x"]
    end

    test "delete_not_found/1 removes one entry" do
      Redirects.record_not_found("/x")
      [entry] = Redirects.list_not_found()

      Redirects.delete_not_found(entry.id)
      assert Redirects.list_not_found() == []
    end

    test "prune_not_found/1 drops entries not seen within the window" do
      Redirects.record_not_found("/neu")
      Redirects.record_not_found("/alt")

      old = DateTime.utc_now() |> DateTime.add(-100, :day) |> DateTime.truncate(:second)

      from(n in NotFoundPath, where: n.path == "/alt")
      |> Repo.update_all(set: [last_seen_at: old])

      assert Redirects.prune_not_found(90) == 1
      assert [%{path: "/neu"}] = Redirects.list_not_found()
    end
  end
end
