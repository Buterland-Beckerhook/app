defmodule :iconv do
  @moduledoc """
  The one function of the `iconv` package that `:mimemail` (gen_smtp) calls to turn a
  MIME part's charset into UTF-8 — implemented in Elixir for the charsets German mail
  actually uses, instead of pulling in a NIF.

  Without a module of this name, `:mimemail.decode/1` crashes on the first non-ASCII
  part (gen_smtp 1.3 always converts to `utf-8//IGNORE`). Handles UTF-8, US-ASCII,
  ISO-8859-1, ISO-8859-15 and Windows-1252; anything else is read as UTF-8 with invalid
  bytes replaced. If the real `iconv` package is ever added, delete this module.
  """

  # Windows-1252 differs from Latin-1 only in 0x80–0x9F.
  @cp1252 %{
    0x80 => 0x20AC,
    0x82 => 0x201A,
    0x83 => 0x0192,
    0x84 => 0x201E,
    0x85 => 0x2026,
    0x86 => 0x2020,
    0x87 => 0x2021,
    0x88 => 0x02C6,
    0x89 => 0x2030,
    0x8A => 0x0160,
    0x8B => 0x2039,
    0x8C => 0x0152,
    0x8E => 0x017D,
    0x91 => 0x2018,
    0x92 => 0x2019,
    0x93 => 0x201C,
    0x94 => 0x201D,
    0x95 => 0x2022,
    0x96 => 0x2013,
    0x97 => 0x2014,
    0x98 => 0x02DC,
    0x99 => 0x2122,
    0x9A => 0x0161,
    0x9B => 0x203A,
    0x9C => 0x0153,
    0x9E => 0x017E,
    0x9F => 0x0178
  }

  # ISO-8859-15 differs from Latin-1 in eight places.
  @latin9 %{
    0xA4 => 0x20AC,
    0xA6 => 0x0160,
    0xA8 => 0x0161,
    0xB4 => 0x017D,
    0xB8 => 0x017E,
    0xBC => 0x0152,
    0xBD => 0x0153,
    0xBE => 0x0178
  }

  @doc "Converts `data` from charset `from` to UTF-8 (`to` is always UTF-8 here)."
  def convert(from, _to, data) when is_binary(data) do
    case from |> to_string() |> String.downcase() |> String.replace(~r/[^a-z0-9]/, "") do
      charset when charset in ~w(utf8 usascii ascii) -> valid_utf8(data)
      charset when charset in ~w(iso88591 latin1 l1) -> map_bytes(data, %{})
      charset when charset in ~w(windows1252 cp1252) -> map_bytes(data, @cp1252)
      charset when charset in ~w(iso885915 latin9) -> map_bytes(data, @latin9)
      _ -> valid_utf8(data)
    end
  end

  defp map_bytes(data, table) do
    for <<byte <- data>>, into: "", do: <<Map.get(table, byte, byte)::utf8>>
  end

  # Replace what isn't UTF-8 instead of failing the whole mail.
  defp valid_utf8(data) do
    case :unicode.characters_to_binary(data, :utf8, :utf8) do
      binary when is_binary(binary) -> binary
      {_, valid, rest} -> valid <> "�" <> valid_utf8(binary_part(rest, 1, byte_size(rest) - 1))
    end
  end
end
