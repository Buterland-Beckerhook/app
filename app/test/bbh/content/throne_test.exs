defmodule Bbh.Content.ThroneTest do
  use Bbh.DataCase, async: true

  alias Bbh.Content.Throne

  @base %{
    "type" => "koenig",
    "begin_year" => 2025,
    "end_year" => 2026,
    "king" => "Max Mustermann",
    "queen" => "Erika Mustermann",
    "article_id" => Ecto.UUID.generate()
  }

  test "a throne is valid without a queen (Königin is optional for every type)" do
    changeset = Throne.changeset(%Throne{}, Map.delete(@base, "queen"))
    assert changeset.valid?
  end

  test "a Jungschützenkönig is valid without a queen" do
    attrs = @base |> Map.put("type", "jungschuetzenkoenig") |> Map.delete("queen")
    assert Throne.changeset(%Throne{}, attrs).valid?
  end

  test "jungschuetzenkoenig is an accepted type" do
    assert "jungschuetzenkoenig" in Throne.types()
    assert Throne.king_only?("jungschuetzenkoenig")
    refute Throne.king_only?("koenig")
  end
end
