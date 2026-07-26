defmodule Mix.Tasks.Bbh.Blz.Strip do
  @shortdoc "Strip the Bundesbank BLZ CSV down to BLZ→{BIC, name} for IBAN lookup"
  @moduledoc """
  Reduce the Deutsche Bundesbank "Bankleitzahlendatei" to the tiny lookup table the
  membership form uses to derive BIC/Kreditinstitut from an IBAN.

      mix bbh.blz.strip path/to/blz-aktuell-csv-data.csv [priv/data/blz.tsv]

  The source is a `;`-separated, `"`-quoted, ISO-8859-1 file with one row per
  bank branch. We keep only the *leading* record per Bankleitzahl (`Merkmal == "1"`,
  the Hauptstelle) that actually carries a BIC, and emit a UTF-8 TSV of

      BLZ<TAB>BIC<TAB>Bezeichnung

  sorted by BLZ. Refresh it whenever the Bundesbank publishes a new quarterly file
  (the download URL is not stable, so this is a manual step); commit the result.
  """
  use Mix.Task

  @default_out "priv/data/blz.tsv"

  @impl true
  def run(args) do
    {input, output} =
      case args do
        [input] -> {input, @default_out}
        [input, output] -> {input, output}
        _ -> Mix.raise("usage: mix bbh.blz.strip <input.csv> [output.tsv]")
      end

    rows =
      input
      |> File.read!()
      # The Bundesbank file is Latin-1; convert to UTF-8 before parsing.
      |> :unicode.characters_to_binary(:latin1)
      |> String.split(~r/\r?\n/, trim: true)
      |> Enum.drop(1)
      |> Enum.flat_map(&parse_line/1)
      |> Enum.uniq_by(fn {blz, _bic, _name} -> blz end)
      |> Enum.sort_by(fn {blz, _bic, _name} -> blz end)

    File.mkdir_p!(Path.dirname(output))
    body = Enum.map_join(rows, "\n", fn {blz, bic, name} -> "#{blz}\t#{bic}\t#{name}" end)
    File.write!(output, body <> "\n")

    Mix.shell().info("Wrote #{length(rows)} BLZ entries to #{output}")
  end

  defp parse_line(line) do
    fields = line |> String.split(";") |> Enum.map(&unquote_field/1)

    case fields do
      [blz, "1" | _] = list ->
        bic = Enum.at(list, 7, "")
        name = Enum.at(list, 2, "")
        if bic == "", do: [], else: [{blz, bic, name}]

      _ ->
        []
    end
  end

  defp unquote_field(field) do
    field |> String.trim() |> String.trim("\"") |> String.trim()
  end
end
