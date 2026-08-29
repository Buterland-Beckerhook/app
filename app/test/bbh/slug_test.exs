defmodule Bbh.SlugTest do
  use ExUnit.Case, async: true

  # Runs the `@doc` example in Bbh.Slug. Without this the example is decoration — no other
  # `doctest` call exists in the suite, so nothing would notice it going stale.
  doctest Bbh.Slug

  alias Bbh.Slug

  describe "slugify/1" do
    test "transliterates umlauts and ß instead of dropping them" do
      assert Slug.slugify("Schützenfest") == "schuetzenfest"
      assert Slug.slugify("Königsball") == "koenigsball"
      assert Slug.slugify("Grüße") == "gruesse"
      assert Slug.slugify("Jungschützenkönig") == "jungschuetzenkoenig"
    end

    test "collapses runs of punctuation and whitespace into a single hyphen" do
      assert Slug.slugify("Ein   Titel!!! Mit --- Zeichen") == "ein-titel-mit-zeichen"
    end

    test "trims leading and trailing hyphens" do
      assert Slug.slugify("  — Vogelschießen 2026 —  ") == "vogelschiessen-2026"
    end

    test "keeps digits" do
      assert Slug.slugify("Kaiserthron 2024/2025") == "kaiserthron-2024-2025"
    end

    test "yields an empty string when nothing survives" do
      # The caller decides what to do with this; `create_article` lets the changeset's
      # `validate_required(:slug)` reject it rather than inventing a slug.
      assert Slug.slugify("!!!") == ""
      assert Slug.slugify("") == ""
    end

    test "is idempotent — slugifying a slug changes nothing" do
      slug = Slug.slugify("Schützenfest 2026 — Königsball!")
      assert Slug.slugify(slug) == slug
    end
  end
end
