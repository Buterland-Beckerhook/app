defmodule Bbh.BlzFixtures do
  @moduledoc "Bundesbank-style BLZ CSV snippets for `Bbh.Blz` and its admin page."

  @header ~s("Bankleitzahl";"Merkmal";"Bezeichnung";"PLZ";"Ort";"Kurzbezeichnung";"PAN";"BIC";"Prüfzifferberechnungsmethode";"Datensatznummer";"Änderungskennzeichen";"Bankleitzahllöschung";"Nachfolge-Bankleitzahl")

  def sample_row, do: {"30000000", "1", "Testbank", "TESTDEFFXXX"}
  def other_row, do: {"40000000", "1", "Andere Bank", "ANDRDEFFXXX"}

  @doc "Rows of `{blz, merkmal, name, bic}` as the Bundesbank file, Latin-1 like the original."
  def bundesbank_csv(rows, encoding \\ :utf8) do
    body =
      Enum.join([@header | Enum.map(rows, &line/1)], "\r\n") <> "\r\n"

    case encoding do
      :utf8 -> body
      :latin1 -> :unicode.characters_to_binary(body, :utf8, :latin1)
    end
  end

  defp line({blz, merkmal, name, bic}) do
    [blz, merkmal, name, "48599", "Gronau", name, "", bic, "00", "000001", "U", "0", "00000000"]
    |> Enum.map_join(";", &~s("#{&1}"))
  end
end
