defmodule BbhWeb.SiteComponentsTest do
  use ExUnit.Case, async: true

  import Phoenix.LiveViewTest
  import BbhWeb.SiteComponents

  @address "vorstand@buterland-beckerhook.de"

  describe "email_link/1" do
    test "the address is never rendered in one piece" do
      html = render_component(&email_link/1, address: @address)

      refute html =~ @address
      refute html =~ "mailto"
      assert html =~ "data-eml"
      assert html =~ ~s(href="/kontakt")
    end

    test "a label hides the address from the visible text" do
      html = render_component(&email_link/1, address: @address, label: "Vorstand anschreiben")

      assert html =~ "Vorstand anschreiben"
      assert html =~ "eml-h"
      refute html =~ @address
    end

    test "a subject becomes an encoded mailto query" do
      html = render_component(&email_link/1, address: @address, subject: "Anfrage Mitgliedschaft")

      assert html =~ ~s(data-eml="?subject=Anfrage+Mitgliedschaft")
    end

    test "a class lands on the anchor" do
      html = render_component(&email_link/1, address: @address, class: "underline")
      assert html =~ "underline"
    end

    test "renders inline, without padding whitespace" do
      # It sits mid-sentence ("Kontakt: <.email_link /> oder ..."), so a stray newline
      # would show up as a space before the following punctuation.
      html = render_component(&email_link/1, address: @address)

      assert html == String.trim(html)
    end
  end

  describe "search_result/1" do
    defp doc(headline),
      do: %{
        url: "/verein/vorstand",
        source_type: "page",
        document_date: nil,
        title: "Vorstand",
        headline: headline
      }

    test "an address in the snippet is obfuscated" do
      html = render_component(&search_result/1, doc: doc("Schreib an #{@address} für Fragen"))

      refute html =~ @address
      assert html =~ ~s(class="eml")
    end

    test "match markers still become <mark>" do
      html = render_component(&search_result/1, doc: doc("Der @@M@@Vorstand@@E@@ tagt"))

      assert html =~ "<mark>Vorstand</mark>"
    end
  end
end
