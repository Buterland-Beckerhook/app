defmodule BbhWeb.EmailObfuscationTest do
  use ExUnit.Case, async: true

  import Phoenix.HTML, only: [safe_to_string: 1]

  alias BbhWeb.EmailObfuscation

  @address "vorstand@buterland-beckerhook.de"

  # A single-dot domain with a 2-char TLD cannot be split into a chunk that still looks
  # like a whole address, so it is blind to a whole class of rewriting bug. Anything
  # about `rewrite/1` gets checked against a multi-label domain too.
  @multi_label "info@mail.example.com"

  # What `assets/js/mail.js` does: take the `.eml` container (or the anchor itself),
  # concatenate its child nodes and skip the `.eml-x` decoys. Every assertion about
  # "the JS gets the right address" goes through this, so the test suite is the
  # contract the enhancer relies on.
  defp js_address(html) do
    html
    |> parse()
    |> box()
    |> text(drop: ["eml-x"])
  end

  # What a human with CSS sees: decoys are hidden, and so is the address container
  # when the link carries its own label.
  defp visible_text(html), do: html |> parse() |> text(drop: ["eml-x", "eml-h"])

  # What a harvester that deletes tags and regexes the rest sees.
  defp stripped(html), do: String.replace(html, ~r/<[^>]*>/, "")

  # How many address containers the markup has. More than one means a pass rescanned
  # its own output and nested them.
  defp boxes(html),
    do: html |> String.split(~r/class="eml(?:"| eml-h")/) |> length() |> Kernel.-(1)

  defp parse(html), do: html |> LazyHTML.from_fragment() |> LazyHTML.to_tree()

  defp box(tree) do
    case find_class(tree, "eml") do
      nil -> tree
      node -> [node]
    end
  end

  defp find_class(nodes, class) when is_list(nodes),
    do: Enum.find_value(nodes, &find_class(&1, class))

  defp find_class({_tag, attrs, children}, class) do
    if class in classes(attrs), do: {nil, [], children}, else: find_class(children, class)
  end

  defp find_class(_other, _class), do: nil

  defp text(nodes, opts) when is_list(nodes),
    do: nodes |> Enum.map(&text(&1, opts)) |> IO.iodata_to_binary()

  defp text(binary, _opts) when is_binary(binary), do: binary

  defp text({_tag, attrs, children}, opts) do
    if Enum.any?(opts[:drop], &(&1 in classes(attrs))), do: "", else: text(children, opts)
  end

  defp text(_other, _opts), do: ""

  defp classes(attrs) do
    Enum.find_value(attrs, [], fn
      {"class", value} -> String.split(value, " ", trim: true)
      _ -> false
    end)
  end

  describe "fragments/1" do
    test "the text pieces reassemble into the address" do
      pieces =
        for {:text, chunk} <- EmailObfuscation.fragments(@address), into: "", do: chunk

      assert pieces == @address
    end

    test "one decoy sits inside the local part and one inside the domain" do
      # Run it a few times — the split points are random, the invariant is not.
      for _ <- 1..50 do
        frags = EmailObfuscation.fragments(@address)
        local_len = @address |> String.split("@") |> hd() |> String.length()

        offsets =
          frags
          |> Enum.reduce({0, []}, fn
            {:text, chunk}, {pos, acc} -> {pos + String.length(chunk), acc}
            {:decoy, _}, {pos, acc} -> {pos, [pos | acc]}
          end)
          |> elem(1)

        assert Enum.any?(offsets, &(&1 >= 1 and &1 <= local_len)),
               "expected a decoy inside the local part, got offsets #{inspect(offsets)}"

        assert Enum.any?(offsets, &(&1 > local_len and &1 < String.length(@address))),
               "expected a decoy inside the domain, got offsets #{inspect(offsets)}"
      end
    end

    test "an address without an @ is passed through unsplit" do
      assert EmailObfuscation.fragments("kein-at-zeichen") == [{:text, "kein-at-zeichen"}]
    end

    test "a missing local part or domain is passed through instead of crashing" do
      # There is no interior cut point, so the invariant cannot hold — better to render
      # a malformed address as-is than to blow up the page it sits on.
      assert EmailObfuscation.fragments("a@") == [{:text, "a@"}]
      assert EmailObfuscation.fragments("@example.com") == [{:text, "@example.com"}]
      assert EmailObfuscation.fragments("") == [{:text, ""}]
      assert @address |> EmailObfuscation.link() |> safe_to_string() =~ "eml-x"
    end

    test "the shortest splittable address still holds the invariant" do
      for _ <- 1..20 do
        assert [{:text, "a"}, {:decoy, _}, {:text, "@"}, {:decoy, _}, {:text, "b"}] =
                 EmailObfuscation.fragments("a@b")
      end
    end
  end

  describe "link/2" do
    defp link(address \\ @address, opts \\ []),
      do: address |> EmailObfuscation.link(opts) |> safe_to_string()

    test "the address never appears in one piece" do
      refute link() =~ @address
    end

    test "the visible text is exactly the address" do
      assert visible_text(link()) == @address
    end

    test "the JS enhancer can reassemble the address" do
      assert js_address(link()) == @address
    end

    test "deleting the tags yields a wrong address, not the real one" do
      text = stripped(link())

      refute text =~ @address
      assert [pseudo] = Regex.run(~r/[\w.+-]+@[\w.-]+\.\w+/, text)
      assert pseudo != @address

      [_local, domain] = String.split(pseudo, "@", parts: 2)
      assert domain != "buterland-beckerhook.de"
    end

    test "no mailto: is in the markup" do
      refute link() =~ "mailto"
    end

    test "without JS the link falls back to the contact form" do
      assert link() =~ ~s(href="/kontakt")
    end

    test "the anchor is marked for the JS enhancer" do
      assert link() =~ "data-eml"
    end

    test "a label replaces the visible address but keeps it reachable for JS" do
      html = link(@address, label: "Mail an den Vorstand")

      assert visible_text(html) == "Mail an den Vorstand"
      assert js_address(html) == @address
      refute html =~ @address
    end

    test "a custom class lands on the anchor" do
      assert link(@address, class: "font-medium underline") =~ "font-medium underline"
    end

    test "a mailto query is carried in data-eml, HTML-escaped" do
      html = link(@address, query: "?subject=Hallo&body=Moin")

      assert html =~ ~s(data-eml="?subject=Hallo&amp;body=Moin")
      assert js_address(html) == @address
    end

    test "special characters in the address are escaped" do
      html = link("a&b@example.com")

      refute html =~ ~r/&(?!amp;)/
      assert js_address(html) == "a&b@example.com"
    end
  end

  describe "text/1" do
    test "renders the address without an anchor" do
      html = @address |> EmailObfuscation.text() |> safe_to_string()

      refute html =~ "<a"
      refute html =~ @address
      assert visible_text(html) == @address
    end
  end

  describe "rewrite/1" do
    test "a mailto link becomes an obfuscated link" do
      html = EmailObfuscation.rewrite(~s(<p><a href="mailto:#{@address}">#{@address}</a></p>))

      refute html =~ "mailto"
      refute html =~ @address
      assert js_address(html) == @address
      assert visible_text(html) == @address
    end

    test "a mailto link with its own text keeps that text" do
      html = EmailObfuscation.rewrite(~s(<a href="mailto:#{@address}">Schreib uns</a>))

      assert visible_text(html) == "Schreib uns"
      assert js_address(html) == @address
      refute html =~ @address
    end

    test "a mailto query survives as data-eml" do
      html = EmailObfuscation.rewrite(~s(<a href="mailto:#{@address}?subject=Hallo">Mail</a>))

      assert html =~ ~s(data-eml="?subject=Hallo")
      assert js_address(html) == @address
    end

    test "an address typed into running text is obfuscated" do
      html = EmailObfuscation.rewrite(~s(<p>Schreib an #{@address} oder ruf an.</p>))

      refute html =~ @address
      assert visible_text(html) == "Schreib an #{@address} oder ruf an."
    end

    test "an address in running text does not become a nested link" do
      html = EmailObfuscation.rewrite(~s(<a href="/verein">Mail an #{@address}</a>))

      assert length(Regex.scan(~r/<a\b/, html)) == 1
      refute html =~ @address
    end

    test "attribute values are left alone" do
      html = EmailObfuscation.rewrite(~s(<img alt="a@b.de" src="/media/x.jpg">))

      assert html =~ ~s(alt="a@b.de")
    end

    test "text without an address is unchanged" do
      html = ~s(<p>Nur Text, kein Klammeraffe.</p>)
      assert EmailObfuscation.rewrite(html) == html
    end

    test "running it twice changes nothing that matters" do
      once = EmailObfuscation.rewrite(~s(<p>Mail: #{@address}</p>))
      twice = EmailObfuscation.rewrite(once)

      refute twice =~ @address
      assert visible_text(twice) == visible_text(once)
    end

    test "a multi-label domain survives a single pass" do
      # A chunk spanning the @ can look like a whole address ("nfo@mail.exa"). If
      # anything rescans the generated markup, the boxes nest and the address the JS
      # reassembles comes out wrong while the visible text still looks right.
      for _ <- 1..200 do
        html = EmailObfuscation.rewrite(~s(<a href="mailto:#{@multi_label}">Mail</a>))

        assert js_address(html) == @multi_label
        assert boxes(html) == 1
      end
    end

    test "a multi-label domain survives a second pass" do
      once = EmailObfuscation.rewrite(~s(<a href="mailto:#{@multi_label}">Mail</a>))
      twice = EmailObfuscation.rewrite(once)

      assert js_address(twice) == @multi_label
      assert visible_text(twice) == visible_text(once)
    end

    test "a cc/bcc address in the query is not left in data-eml" do
      html = EmailObfuscation.rewrite(~s(<a href="mailto:#{@address}?cc=kasse@example.com">M</a>))

      refute html =~ "kasse@example.com"
      assert html =~ "cc=kasse%40example.com"
    end

    test "inline formatting in the link text is kept" do
      html =
        EmailObfuscation.rewrite(
          ~s(<a href="mailto:#{@address}"><strong>#{@address}</strong></a>)
        )

      assert html =~ "<strong>"
      refute html =~ @address
      assert js_address(html) == @address
      assert visible_text(html) == @address
    end

    test "escaped entities in the href are decoded once" do
      html = EmailObfuscation.rewrite(~s(<a href="mailto:#{@address}?subject=A&amp;B">M</a>))

      assert html =~ ~s(data-eml="?subject=A&amp;B")
      refute html =~ "&amp;amp;"
    end

    test "non-binaries pass through" do
      assert EmailObfuscation.rewrite(nil) == nil
    end
  end
end
