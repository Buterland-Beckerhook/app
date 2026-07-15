defmodule Bbh.PlaceholdersTest do
  use Bbh.DataCase, async: true

  import Bbh.ClubFixtures

  alias Bbh.Placeholders

  describe "render/1" do
    test "resolves a role token to the current holder's field" do
      person_fixture(role: "geschaeftsfuehrer", name: "Erika Beispiel", email: "gf@example.org")

      assert Placeholders.render("Verantwortlich: {{ geschaeftsfuehrer.name }}") ==
               "Verantwortlich: Erika Beispiel"

      assert Placeholders.render("{{ geschaeftsfuehrer.email }}") == "gf@example.org"
      assert Placeholders.render("{{ geschaeftsfuehrer.role }}") == "Geschäftsführer"
    end

    test "picks the current/last holder: no end year wins, else the latest year_end" do
      person_fixture(role: "praesident", name: "Alt", year_end: 2010)
      person_fixture(role: "praesident", name: "Neuer", year_end: 2020)
      person_fixture(role: "praesident", name: "Amtierend", year_end: nil)

      assert Placeholders.render("{{ praesident.name }}") == "Amtierend"
    end

    test "falls back to the highest year_end when nobody is currently serving" do
      person_fixture(role: "kassierer", name: "Frueher", year_end: 2005)
      person_fixture(role: "kassierer", name: "Zuletzt", year_end: 2015)

      assert Placeholders.render("{{ kassierer.name }}") == "Zuletzt"
    end

    test "valid token with no holder renders empty" do
      assert Placeholders.render("X{{ praesident.name }}Y") == "XY"
    end

    test "unknown role or field is left untouched" do
      assert Placeholders.render("{{ chef.name }}") == "{{ chef.name }}"
      assert Placeholders.render("{{ praesident.phone }}") == "{{ praesident.phone }}"
    end

    test "escapes resolved values" do
      person_fixture(role: "schriftfuehrer", name: "A & B <script>")
      assert Placeholders.render("{{ schriftfuehrer.name }}") == "A &amp; B &lt;script&gt;"
    end

    test "passes nil and non-binaries through" do
      assert Placeholders.render(nil) == nil
    end
  end
end
