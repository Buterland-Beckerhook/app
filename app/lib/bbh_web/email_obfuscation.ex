defmodule BbhWeb.EmailObfuscation do
  @moduledoc """
  Renders e-mail addresses so that harvesters get a wrong address and humans get the
  right one — without needing JavaScript.

  The address is split into chunks at render time and decoy elements are woven in
  between; a `display: none` rule on `.eml-x` (see `assets/css/app.css`) hides them:

      <a href="/kontakt" data-eml=""><span class="eml"
        ><span>vorst</span><span class="eml-x" aria-hidden="true">Qkz</span
        ><span>and@buter</span><span class="eml-x" aria-hidden="true">NwtR</span
        ><span>land-beckerhook.de</span></span></a>

  With CSS the text reads `vorstand@buterland-beckerhook.de`, is selectable and copies
  cleanly (`display: none` content is left out of a selection). Screen readers read the
  same thing, because `display: none` removes the decoys from the accessibility tree.

  ## The decoy invariant

  `fragments/1` guarantees **one decoy strictly inside the local part and one strictly
  inside the domain**, never at either end of the address. A harvester that deletes the
  tags and runs a regex over what is left therefore does not come up empty — it comes up
  with `vorstQkzand@buterNwtRland-beckerhook.de`, a syntactically valid address on a
  domain that does not exist. It reads as a hit, so the miss is never noticed. The decoy
  in the *domain* is the important one: were the junk confined to the local part, the
  spam would land on our own domain as an undeliverable mailbox.

  Split points and decoy strings are random per render, so there is no fixed pattern to
  learn across pages.

  ## JavaScript is enhancement only

  There is no encoded payload and no key — `assets/js/mail.js` reassembles the address
  from the DOM by skipping the `.eml-x` children and upgrades the anchor's `href` from
  `/kontakt` to `mailto:`. It does that on the first interaction, not on load, so a
  headless scraper that merely renders the page and collects `href`s gets the contact
  form. The public site is served as dead views, so this has to be a delegated listener
  rather than a `phx-hook`; inline handlers are out anyway (`BbhWeb.Plugs.CSP`).

  ## What this does not do

  A scraper driving a real browser can read `innerText` and gets the address. That is the
  unavoidable cost of keeping it readable without JavaScript. This defeats the fetch-and-
  regex harvesters, which is the bulk of the traffic; the contact form (`docs/adr/0003`)
  and server-side spam filtering remain the second line.

  See `docs/adr/0005-email-obfuscation.md`.
  """

  use BbhWeb, :verified_routes

  import Phoenix.HTML, only: [safe_to_string: 1]

  @decoy_alphabet "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ"
  @decoy_lengths 3..8

  # ASCII only — an internationalised address (müller@…) typed into the copy is not
  # recognised. Every address the club actually publishes is ASCII.
  @address_pattern "[A-Za-z0-9._%+\\-]+@[A-Za-z0-9.\\-]+\\.[A-Za-z]{2,}"

  # One pass, three branches, in this order:
  #
  #   1. a whole `mailto:` anchor,
  #   2. any other tag — handed back untouched, which is what keeps an address in an
  #      attribute value from ever being rewritten,
  #   3. a bare address in a text node.
  #
  # It has to be a single `Regex.replace`: a second pass would rescan the markup the
  # first one produced, and a chunk spanning the `@` can still look like a whole
  # address (`nfo@mail.exa`), which would nest one obfuscated box inside another.
  #
  # Branch 1 depends on `Bbh.Html.sanitize/1` having re-serialized the stored HTML:
  # double-quoted attributes and a balanced `</a>`. An unbalanced or single-quoted
  # anchor would fall through to branch 2 and keep its address in the clear.
  @rewritable ~r/<a\b[^>]*\bhref="mailto:([^"]*)"[^>]*>(.*?)<\/a>|(<[^>]*>)|(#{@address_pattern})/is

  @doc """
  Split `address` into `{:text, chunk}` and `{:decoy, junk}` pieces.

  Upholds the decoy invariant described in the module doc. An input without a usable
  local part is returned as a single chunk rather than mangled.
  """
  def fragments(address) when is_binary(address) do
    case String.split(address, "@", parts: 2) do
      [local, domain] -> split(address, String.length(local), String.length(domain))
      [_no_at] -> [{:text, address}]
    end
  end

  @doc """
  An obfuscated `mailto:` link.

  Without JavaScript the anchor points at the contact form and shows the address;
  `mail.js` upgrades the `href` on the first interaction.

  Options:

    * `:label` — link text to show instead of the address. A binary is escaped, a
      `{:safe, iodata}` tuple is used verbatim. The address moves into a hidden
      container where the enhancer still finds it.
    * `:class` — classes for the anchor.
    * `:href` — no-JS fallback target, defaults to the contact form.
    * `:query` — `mailto:` suffix such as `"?subject=Hallo"`, kept in `data-eml`.
  """
  def link(address, opts \\ []) when is_binary(address) do
    inner =
      case opts[:label] do
        nil -> box(address, "eml")
        label -> [label_html(label), box(address, "eml eml-h")]
      end

    {:safe,
     [
       ~s(<a href="),
       escape(opts[:href] || ~p"/kontakt"),
       ~s(" data-eml="),
       escape(opts[:query] || ""),
       ~s("),
       class_attr(opts[:class]),
       ~s(>),
       inner,
       ~s(</a>)
     ]}
  end

  @doc "The obfuscated address as plain inline markup, without an anchor."
  def text(address) when is_binary(address), do: {:safe, box(address, "eml")}

  @doc """
  Obfuscate every address in already-rendered HTML.

  Runs at render time over sanitized rich text: first `mailto:` anchors, then addresses
  typed straight into the copy. A bare address becomes inline markup rather than a link,
  because it may well sit inside an anchor already and anchors cannot nest — editors who
  want it clickable set a proper link in the editor.

  Passes non-binaries through, like `Bbh.Placeholders.render/1`.
  """
  def rewrite(html) when is_binary(html) do
    # Guards, not positional matching: only one branch of @rewritable ever captures a
    # non-empty group, and neither a tag nor an address can match the empty string.
    Regex.replace(@rewritable, html, fn
      whole, _target, _inner, tag, _address when tag != "" -> whole
      _whole, _target, _inner, _tag, address when address != "" -> obfuscate(address)
      _whole, target, inner, _tag, _address -> mailto_link(target, inner)
    end)
  end

  def rewrite(other), do: other

  defp obfuscate(address), do: address |> text() |> safe_to_string()

  defp mailto_link(target, inner) do
    {address, query} = split_query(unescape(target))

    address
    |> link([query: query] ++ label_opt(inner, address))
    |> safe_to_string()
  end

  # Plain text that just repeats the address needs no label — the default shape already
  # renders it. Everything else is kept, including inline formatting, and rewritten in
  # turn so an address inside the label is obfuscated too. That leaves a labelled link
  # whose label already shows the address carrying it twice, once hidden; harmless,
  # and `mail.js` reads whichever container comes first.
  defp label_opt(inner, address) do
    trimmed = String.trim(inner)
    bare_address? = not String.contains?(trimmed, "<") and equal?(trimmed, address)

    if trimmed == "" or bare_address?,
      do: [],
      else: [label: {:safe, rewrite(inner)}]
  end

  defp equal?(a, b), do: String.downcase(a) == String.downcase(b)

  # `@` becomes `%40` — still a valid `mailto:` URL, but a `?cc=` or `?body=` carrying
  # another address no longer hands it to a harvester through the `data-eml` attribute.
  defp split_query(target) do
    case String.split(target, "?", parts: 2) do
      [address, query] -> {address, "?" <> String.replace(query, "@", "%40")}
      [address] -> {address, ""}
    end
  end

  # The stored href is escaped; undo it so re-escaping does not double up. `&amp;` has
  # to go last, or `&amp;lt;` would collapse into a literal `<`.
  @entities [{"&lt;", "<"}, {"&gt;", ">"}, {"&quot;", "\""}, {"&#39;", "'"}, {"&amp;", "&"}]

  defp unescape(target) do
    Enum.reduce(@entities, target, fn {entity, char}, acc ->
      String.replace(acc, entity, char)
    end)
  end

  defp box(address, class) do
    [
      ~s(<span class="),
      class,
      ~s(">),
      Enum.map(fragments(address), &fragment/1),
      ~s(</span>)
    ]
  end

  # Decoys come from a fixed letter alphabet, so there is nothing to escape in them.
  defp fragment({:text, chunk}), do: [~s(<span>), escape(chunk), ~s(</span>)]

  defp fragment({:decoy, junk}),
    do: [~s(<span class="eml-x" aria-hidden="true">), junk, ~s(</span>)]

  defp label_html({:safe, iodata}), do: iodata
  defp label_html(label) when is_binary(label), do: escape(label)

  defp class_attr(nil), do: []
  defp class_attr(class), do: [~s( class="), escape(class), ~s(")]

  # Nothing to cut into: the invariant needs a character on each side of the `@`.
  # `rewrite/1` never gets here, but `link/2` takes whatever a template hands it.
  defp split(address, local_len, domain_len) when local_len < 1 or domain_len < 1,
    do: [{:text, address}]

  defp split(address, local_len, domain_len) do
    # `cut1` lands inside the local part (1..local_len), `cut2` inside the domain
    # (local_len+1 .. len-1) — never at either end, which is what the invariant needs.
    cut1 = :rand.uniform(local_len)
    cut2 = local_len + :rand.uniform(domain_len)

    {chunk1, rest} = String.split_at(address, cut1)
    {chunk2, chunk3} = String.split_at(rest, cut2 - cut1)

    [
      {:text, chunk1},
      {:decoy, decoy()},
      {:text, chunk2},
      {:decoy, decoy()},
      {:text, chunk3}
    ]
  end

  # Junk, not a secret — one plain PRNG is enough, and it avoids the modulo bias of
  # folding random bytes onto a 52-letter alphabet.
  defp decoy do
    for _ <- 1..Enum.random(@decoy_lengths),
        into: "",
        do: <<:binary.at(@decoy_alphabet, :rand.uniform(52) - 1)>>
  end

  defp escape(value), do: Plug.HTML.html_escape(value)
end
