defmodule BbhWeb.Admin.MediaPickerComponentTest do
  use Bbh.DataCase, async: true

  alias Bbh.Media.Upload
  alias BbhWeb.Admin.MediaPickerComponent, as: Picker

  describe "insert_html/1" do
    test "images become an <img> tag with escaped alt" do
      upload = %Upload{storage_key: "abc.jpg", content_type: "image/jpeg", title: "A & B"}
      assert Picker.insert_html(upload) == ~s(<img src="/media/abc.jpg" alt="A &amp; B">)
    end

    test "falls back to the filename when there is no title" do
      upload = %Upload{storage_key: "x.png", content_type: "image/png", filename: "foto.png"}
      assert Picker.insert_html(upload) == ~s(<img src="/media/x.png" alt="foto.png">)
    end

    test "non-images become a download link" do
      upload = %Upload{storage_key: "doc.pdf", content_type: "application/pdf", title: "Satzung"}
      assert Picker.insert_html(upload) == ~s(<a href="/media/doc.pdf">Satzung</a>)
    end
  end
end
