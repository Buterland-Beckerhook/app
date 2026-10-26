defmodule Mix.Tasks.Bbh.Blz.Strip do
  @shortdoc "Strip the Bundesbank BLZ CSV down to BLZ→{BIC, name} for IBAN lookup"
  @moduledoc """
  Reduce the Deutsche Bundesbank "Bankleitzahlendatei" to the tiny lookup table the
  membership form uses to derive BIC/Kreditinstitut from an IBAN.

      mix bbh.blz.strip path/to/blz-aktuell-csv-data.csv [priv/data/blz.tsv]

  Parsing is `Bbh.Blz.parse_bundesbank/1`, the same an admin upload at
  `/admin/bankleitzahlen` goes through; the output is a UTF-8 TSV of

      BLZ<TAB>BIC<TAB>Bezeichnung

  sorted by BLZ. The running site is normally refreshed through that upload; use this
  task to refresh the copy shipped in the release, then commit the result.
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

    case input |> File.read!() |> Bbh.Blz.parse_bundesbank() do
      {:ok, table} ->
        File.mkdir_p!(Path.dirname(output))
        File.write!(output, Bbh.Blz.encode(table))
        Mix.shell().info("Wrote #{map_size(table)} BLZ entries to #{output}")

      {:error, :too_few_entries} ->
        Mix.raise("#{input} does not look like the Bundesbank BLZ file (too few entries)")
    end
  end
end
