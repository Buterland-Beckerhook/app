defmodule Bbh.Tickets.InboundMail do
  @moduledoc """
  A raw mail from the Postfach mailbox, parsed into what the import needs
  (`Bbh.Tickets.Importer`). MIME decoding (multipart, quoted-printable/base64, RFC 2047
  headers, charsets) is gen_smtp's `:mimemail` with the `:iconv` module of this app.

  Text only: the `text/plain` part, else the HTML part turned into text (links kept as
  `text (url)`). Mail HTML is never rendered anywhere.
  """

  defstruct [
    :message_id,
    :message_id_hash,
    :subject,
    :from_name,
    :from_email,
    :original_to,
    :auto_submitted,
    :precedence,
    :spam_score,
    :report?,
    text: "",
    to: [],
    cc: [],
    delivered_to: [],
    reply_ids: [],
    attachments: []
  ]

  @doc "Parses a raw mail. `{:ok, %InboundMail{}}` or `{:error, :unparseable}`."
  def parse(raw) when is_binary(raw) do
    {type, subtype, headers, params, body} = :mimemail.decode(raw)
    header = &header(headers, &1)

    message_id = header.("Message-ID")

    mail = %__MODULE__{
      message_id: message_id,
      # The raw mail's hash stands in for a missing Message-ID, so the import stays
      # idempotent either way.
      message_id_hash: sha256(message_id || raw),
      subject: header.("Subject") |> clean(),
      original_to: headers |> all(["X-Original-To"]) |> List.first() |> address(),
      delivered_to: headers |> all(["Delivered-To"]) |> Enum.map(&address/1),
      auto_submitted: header.("Auto-Submitted") |> downcase(),
      precedence: header.("Precedence") |> downcase(),
      spam_score: spam_score(headers),
      report?: String.downcase("#{type}/#{subtype}") == "multipart/report",
      to: header.("To") |> addresses() |> Enum.map(&elem(&1, 1)),
      cc: header.("Cc") |> addresses() |> Enum.map(&elem(&1, 1)),
      reply_ids: message_ids(header.("In-Reply-To")) ++ message_ids(header.("References"))
    }

    {from_name, from_email} =
      case addresses(header.("From")) do
        [first | _] -> first
        [] -> {nil, nil}
      end

    parts = flatten({type, subtype, headers, params, body})

    {:ok,
     %{
       mail
       | from_name: from_name,
         from_email: from_email,
         text: text(parts),
         attachments: attachments(parts)
     }}
  rescue
    _ -> {:error, :unparseable}
  catch
    _, _ -> {:error, :unparseable}
  end

  @doc "SHA-256 of a Message-ID (or any value), hex — how inbound ids are stored."
  def sha256(value), do: :crypto.hash(:sha256, String.trim(value)) |> Base.encode16(case: :lower)

  ## Headers

  defp header(headers, name) do
    Enum.find_value(headers, fn {key, value} ->
      if String.downcase(key) == String.downcase(name), do: value
    end)
  end

  # Every occurrence of a header, top-most first (the order in the mail).
  defp all(headers, names) do
    names = Enum.map(names, &String.downcase/1)
    for {key, value} <- headers, String.downcase(key) in names, do: value
  end

  defp downcase(nil), do: nil
  defp downcase(value), do: value |> String.trim() |> String.downcase()

  defp clean(nil), do: nil
  defp clean(value), do: value |> String.replace(~r/\s+/, " ") |> String.trim()

  # rspamd via mailcow: "X-Rspamd-Score: 3.45" or "X-Spamd-Result: default: False [3.45 / 15.00]".
  defp spam_score(headers) do
    with nil <- headers |> header("X-Rspamd-Score") |> to_float(),
         result when is_binary(result) <- header(headers, "X-Spamd-Result"),
         [_, score] <- Regex.run(~r/\[\s*(-?\d+(?:\.\d+)?)\s*\//, result) do
      to_float(score)
    else
      score when is_float(score) -> score
      _ -> nil
    end
  end

  defp to_float(nil), do: nil

  defp to_float(value) do
    case Float.parse(String.trim(value)) do
      {float, _} -> float
      :error -> nil
    end
  end

  defp message_ids(nil), do: []
  defp message_ids(value), do: Regex.scan(~r/<[^<>\s]+>/, value) |> List.flatten()

  @doc false
  # `[{name, address}]` from an address header; addresses lower-cased.
  def addresses(nil), do: []

  def addresses(value) do
    case :smtp_util.parse_rfc5322_addresses(value) do
      {:ok, list} ->
        for {name, addr} <- list, is_list(addr) or is_binary(addr) do
          {name && to_string(name), addr |> to_string() |> String.downcase()}
        end

      _ ->
        Regex.scan(~r/[^\s<>,"]+@[^\s<>,"]+/, value)
        |> List.flatten()
        |> Enum.map(&{nil, String.downcase(&1)})
    end
  rescue
    _ -> []
  end

  defp address(nil), do: nil

  defp address(value) do
    case addresses(value) do
      [{_, addr} | _] ->
        addr

      [] ->
        value
        |> String.trim()
        |> String.trim_leading("<")
        |> String.trim_trailing(">")
        |> String.downcase()
    end
  end

  ## Body

  # The leaf parts in order, as `{type/subtype, disposition, params, body}`.
  defp flatten({type, subtype, _headers, params, body}) when is_list(body) do
    if String.downcase("#{type}/#{subtype}") == "message/rfc822",
      do: [{"message/rfc822", "attachment", params, ""}],
      else: Enum.flat_map(body, &flatten/1)
  end

  defp flatten({type, subtype, _headers, params, body}) when is_binary(body) do
    [
      {String.downcase("#{type}/#{subtype}"), Map.get(params, :disposition, "inline"), params,
       body}
    ]
  end

  defp flatten(_), do: []

  defp text(parts) do
    inline = Enum.reject(parts, &attachment?/1)

    cond do
      plain = Enum.find(inline, &(elem(&1, 0) == "text/plain")) ->
        plain |> elem(3) |> normalize()

      html = Enum.find(inline, &(elem(&1, 0) == "text/html")) ->
        html |> elem(3) |> html_to_text()

      true ->
        ""
    end
  end

  defp attachments(parts) do
    for {type, _disposition, params, body} = part <- parts, attachment?(part) do
      %{
        filename: filename(params) || "anhang",
        content_type: type,
        data: body,
        size: byte_size(body)
      }
    end
  end

  defp attachment?({type, disposition, params, _body}) do
    String.downcase(disposition || "") == "attachment" or
      (filename(params) != nil and type not in ["text/plain", "text/html"])
  end

  defp filename(params) do
    disposition = Map.get(params, :disposition_params, [])
    content = Map.get(params, :content_type_params, [])

    Enum.find_value(disposition ++ content, fn {key, value} ->
      if String.downcase(key) in ["filename", "name"], do: decode_filename(value)
    end)
  end

  # Some clients put RFC 2047 or RFC 2231 encoding into the filename parameter.
  defp decode_filename(value) do
    cond do
      String.contains?(value, "=?") ->
        decode_words(value)

      match = Regex.run(~r/^([\w-]+)'[\w-]*'(.+)$/, value) ->
        [_, charset, encoded] = match
        :iconv.convert(charset, "utf-8", URI.decode(encoded))

      true ->
        value
    end
  rescue
    _ -> value
  end

  # RFC 2047 encoded words ("=?UTF-8?B?…?=", "=?iso-8859-1?Q?…?=").
  defp decode_words(value) do
    ~r/=\?([^?]+)\?([bBqQ])\?([^?]*)\?=/
    |> Regex.replace(value, fn _, charset, encoding, text ->
      bytes =
        case String.upcase(encoding) do
          "B" -> Base.decode64!(text, padding: false)
          "Q" -> text |> String.replace("_", " ") |> :mimemail.decode_quoted_printable()
        end

      :iconv.convert(charset, "utf-8", bytes)
    end)
    |> String.replace(~r/\?=\s+=\?/, "")
  end

  defp normalize(text) do
    text
    |> String.replace("\r\n", "\n")
    |> String.trim()
  end

  @doc false
  def html_to_text(html) do
    html
    |> String.replace(~r/<(script|style|head)\b.*?<\/\1>/is, "")
    |> String.replace(~r/<a\b[^>]*href\s*=\s*"([^"]*)"[^>]*>(.*?)<\/a>/is, "\\2 (\\1)")
    |> String.replace(~r/<br\s*\/?>/i, "\n")
    |> String.replace(~r/<\/(p|div|li|tr|h[1-6]|blockquote)>/i, "\n")
    |> String.replace(~r/<li\b[^>]*>/i, "- ")
    |> HtmlSanitizeEx.strip_tags()
    |> decode_entities()
    |> String.replace(~r/[ \t]+/, " ")
    |> String.replace(~r/ *\n */, "\n")
    |> String.replace(~r/\n{3,}/, "\n\n")
    |> String.trim()
  end

  @entities %{
    "&amp;" => "&",
    "&lt;" => "<",
    "&gt;" => ">",
    "&quot;" => "\"",
    "&#39;" => "'",
    "&apos;" => "'",
    "&nbsp;" => " "
  }

  defp decode_entities(text) do
    text =
      Enum.reduce(@entities, text, fn {entity, char}, acc -> String.replace(acc, entity, char) end)

    Regex.replace(~r/&#(x?)([0-9a-f]+);/i, text, fn whole, hex, digits ->
      code = if hex == "", do: Integer.parse(digits), else: Integer.parse(digits, 16)

      case code do
        {n, ""} when n in 32..0x10FFFF -> <<n::utf8>>
        _ -> whole
      end
    end)
  end
end
