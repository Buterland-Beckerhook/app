defmodule Bbh.HtmlTest do
  use ExUnit.Case, async: true

  alias Bbh.Html

  describe "sanitize/1" do
    test "passes through nil and non-binaries" do
      assert Html.sanitize(nil) == nil
      assert Html.sanitize(42) == 42
    end

    test "keeps Quill's semantic formatting (headings, lists, marks, links)" do
      html =
        "<h2>Titel</h2><p><strong>fett</strong> und <em>kursiv</em></p>" <>
          "<ul><li>a</li></ul><ol><li>b</li></ol>" <>
          ~s(<a href="https://example.com">link</a>)

      out = Html.sanitize(html)

      assert out =~ "<h2>Titel</h2>"
      assert out =~ "<strong>fett</strong>"
      assert out =~ "<em>kursiv</em>"
      assert out =~ "<ul><li>a</li></ul>"
      assert out =~ "<ol><li>b</li></ol>"
      assert out =~ ~s(<a href="https://example.com")
    end

    test "keeps whitelisted alignment and image-size classes" do
      assert Html.sanitize(~s(<p class="ql-align-center">x</p>)) =~ ~s(class="ql-align-center")
      assert Html.sanitize(~s(<p class="ql-align-right">x</p>)) =~ ~s(class="ql-align-right")

      assert Html.sanitize(~s(<img src="/media/1.jpg" class="bbh-img-md">)) =~
               ~s(class="bbh-img-md")
    end

    test "keeps only whitelisted tokens within a class attribute" do
      out = Html.sanitize(~s(<p class="ql-align-center fixed inset-0">x</p>))

      assert out =~ ~s(class="ql-align-center")
      refute out =~ "fixed"
      refute out =~ "inset-0"
    end

    test "drops the class attribute entirely when nothing survives" do
      out = Html.sanitize(~s(<p class="evil-class another">x</p>))

      refute out =~ "class="
      assert out =~ "<p>x</p>"
    end

    test "restores normal spaces from Quill's &nbsp; escaping (placeholders, wrapping)" do
      # getSemanticHTML() escapes every space; both the entity and the U+00A0 char
      # must come back as a plain space so {{ placeholder }} still resolves.
      assert Html.sanitize("<p>{{&nbsp;rolle.name&nbsp;}}</p>") == "<p>{{ rolle.name }}</p>"
      assert Html.sanitize("<p>a b</p>") == "<p>a b</p>"
    end

    test "permits scheme-less media image and link URLs" do
      assert Html.sanitize(~s(<img src="/media/2024/x.jpg" alt="Foto">)) =~
               ~s(src="/media/2024/x.jpg")

      assert Html.sanitize(~s(<a href="/media/2024/doc.pdf">PDF</a>)) =~
               ~s(href="/media/2024/doc.pdf")
    end

    test "strips scripts, inline handlers, styles and dangerous URLs" do
      # The <script> element is removed; its inert text may remain but can't run.
      refute Html.sanitize("<script>alert(1)</script>hi") =~ "<script"
      refute Html.sanitize(~s|<img src="/media/x.jpg" onerror="alert(1)">|) =~ "onerror"
      refute Html.sanitize(~s|<p style="position:fixed">x</p>|) =~ "style"
      refute Html.sanitize(~s|<a href="javascript:alert(1)">x</a>|) =~ "javascript:"
      refute Html.sanitize(~s|<img src="data:text/html;base64,AAAA">|) =~ "data:"
    end
  end

  describe "sanitize/1 paragraph merging" do
    test "joins consecutive paragraphs with <br />, blank line starts a new <p>" do
      html =
        "<p>intro</p><p></p>" <>
          "<p>line 1</p><p>line 2</p><p>line 3</p>" <>
          "<p></p><p>outro</p>"

      assert Html.sanitize(html) ==
               "<p>intro</p><p>line 1<br />line 2<br />line 3</p><p>outro</p>"
    end

    test "treats a <p><br></p> blank line as a paragraph break too" do
      assert Html.sanitize("<p>a</p><p><br></p><p>b</p>") == "<p>a</p><p>b</p>"
    end

    test "keeps an existing single <br /> inside a paragraph" do
      assert Html.sanitize("<p>a<br>b</p>") == "<p>a<br />b</p>"
    end

    test "does not merge paragraphs with differing alignment" do
      html = ~s(<p class="ql-align-center">a</p><p class="ql-align-right">b</p>)
      assert Html.sanitize(html) == html
    end

    test "merges paragraphs that share the same alignment class" do
      html = ~s(<p class="ql-align-center">a</p><p class="ql-align-center">b</p>)
      assert Html.sanitize(html) == ~s(<p class="ql-align-center">a<br />b</p>)
    end

    test "headings and lists remain paragraph boundaries (never merged in)" do
      html = "<h2>Titel</h2><p>a</p><p>b</p><ul><li>x</li></ul><p>c</p>"

      assert Html.sanitize(html) ==
               "<h2>Titel</h2><p>a<br />b</p><ul><li>x</li></ul><p>c</p>"
    end
  end

  describe "to_editor/1" do
    test "passes through nil and non-binaries" do
      assert Html.to_editor(nil) == nil
      assert Html.to_editor(42) == 42
    end

    test "inserts a blank paragraph between adjacent real paragraphs" do
      assert Html.to_editor("<p>a<br />b</p><p>c</p>") ==
               "<p>a<br />b</p><p></p><p>c</p>"
    end

    test "does not insert a blank between a paragraph and a non-paragraph block" do
      assert Html.to_editor("<p>a</p><ul><li>x</li></ul>") ==
               "<p>a</p><ul><li>x</li></ul>"
    end

    test "round-trips through the editor stably (paste flattens <br /> to paragraphs)" do
      stored = "<p>intro</p><p>a<br />b<br />c</p><p>outro</p>"

      # Quill has no soft break: pasting turns each <br /> into its own paragraph.
      flattened = String.replace(Html.to_editor(stored), ~r{<br\s*/?>}, "</p><p>")

      assert Html.sanitize(flattened) == stored
    end
  end

  describe "to_text/1" do
    test "strips tags and collapses whitespace" do
      assert Html.to_text("<p>a</p><p>b</p>") == "a b"
      assert Html.to_text(nil) == ""
    end

    test "decodes the entities the editor emits" do
      assert Html.to_text("Fisch &amp; Chips") == "Fisch & Chips"
      assert Html.to_text("a&nbsp;b") == "a b"
    end
  end
end
