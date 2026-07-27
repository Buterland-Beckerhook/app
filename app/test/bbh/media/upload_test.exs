defmodule Bbh.Media.UploadTest do
  use Bbh.DataCase, async: true

  alias Bbh.Media.Upload
  alias Ecto.Changeset

  @base %{"storage_key" => "2026/abc.jpg", "filename" => "abc.jpg"}

  describe "changeset/2 (create)" do
    test "defaults copyright to the club when none is given" do
      cs = Upload.changeset(%Upload{}, @base)
      assert Changeset.get_field(cs, :copyright) == "Buterland-Beckerhook e.V."
    end

    test "keeps an explicit copyright" do
      cs = Upload.changeset(%Upload{}, Map.put(@base, "copyright", "Foto: Max"))
      assert Changeset.get_field(cs, :copyright) == "Foto: Max"
    end
  end

  describe "update_changeset/2 (admin edit)" do
    test "does not re-inject a default so admins can clear it" do
      cs = Upload.update_changeset(%Upload{copyright: "Alt"}, %{"copyright" => ""})
      assert Changeset.get_field(cs, :copyright) in [nil, ""]
    end
  end
end
