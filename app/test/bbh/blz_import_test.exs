defmodule Bbh.BlzImportTest do
  # Imports swap the global table in persistent_term, so this must not run beside the
  # async tests that read it.
  use ExUnit.Case, async: false

  alias Bbh.Blz

  import Bbh.BlzFixtures

  setup do
    on_exit(fn -> :ok = Blz.reset() end)
  end

  describe "parse_bundesbank/1" do
    test "keeps the Hauptstelle with a BIC, once per BLZ" do
      csv =
        bundesbank_csv([
          {"10000000", "1", "Bundesbank", "MARKDEF1100"},
          {"10000000", "2", "Bundesbank Filiale", "MARKDEF1100"},
          {"20000000", "1", "Ohne BIC", ""},
          {"30000000", "1", "Testbank", "TESTDEFFXXX"},
          {"kaputt", "1", "Falsche BLZ", "TESTDEFFXXX"}
        ])

      assert {:ok, table} = Blz.parse_bundesbank(csv)

      assert table == %{
               "10000000" => {"MARKDEF1100", "Bundesbank"},
               "30000000" => {"TESTDEFFXXX", "Testbank"}
             }
    end

    test "reads the Latin-1 original as well as a UTF-8 re-save" do
      rows = [{"10000000", "1", "Sparkasse Münster", "WELADED1MST"}, sample_row()]

      for csv <- [bundesbank_csv(rows), bundesbank_csv(rows, :latin1)] do
        assert {:ok, %{"10000000" => {_, "Sparkasse Münster"}}} = Blz.parse_bundesbank(csv)
      end
    end

    test "refuses a file that is too small to be the real one" do
      assert {:error, :too_few_entries} =
               Blz.parse_bundesbank("Bankleitzahl;Merkmal\nfoo;bar\n")
    end
  end

  describe "import/1, diff/1 and reset/0" do
    test "an imported table replaces the shipped one until it is removed" do
      assert %{source: :shipped} = Blz.status()

      {:ok, table} = Blz.parse_bundesbank(bundesbank_csv([sample_row(), other_row()]))
      assert :ok = Blz.import(table)

      assert %{source: :upload, entries: 2, uploaded_at: %DateTime{}} = Blz.status()
      assert {:ok, %{bic: "TESTDEFFXXX"}} = Blz.lookup_by_iban("DE00 3000 0000 0000 0000 00")
      assert :error = Blz.lookup_by_iban("DE00 4005 0150 0000 0000 00")

      assert :ok = Blz.reset()
      assert %{source: :shipped} = Blz.status()
      assert {:ok, %{bic: "WELADED1MST"}} = Blz.lookup_by_iban("DE00 4005 0150 0000 0000 00")
    end

    test "diff/1 sorts the new table into added, changed and removed" do
      {:ok, old} = Blz.parse_bundesbank(bundesbank_csv([sample_row(), other_row()]))
      :ok = Blz.import(old)

      {:ok, new} =
        Blz.parse_bundesbank(
          bundesbank_csv([
            {"30000000", "1", "Testbank neu", "TESTDEFFXXX"},
            {"50000000", "1", "Neubank", "NEUBDEFFXXX"}
          ])
        )

      assert Blz.diff(new) == %{
               added: [{"50000000", "NEUBDEFFXXX", "Neubank"}],
               removed: [{"40000000", "ANDRDEFFXXX", "Andere Bank"}],
               changed: [
                 {"30000000", {"TESTDEFFXXX", "Testbank"}, {"TESTDEFFXXX", "Testbank neu"}}
               ]
             }
    end
  end
end
