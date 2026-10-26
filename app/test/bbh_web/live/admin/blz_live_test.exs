defmodule BbhWeb.Admin.BlzLiveTest do
  # Applying an upload swaps the global BLZ table, so not beside async tests reading it.
  use BbhWeb.ConnCase, async: false

  import Phoenix.LiveViewTest
  import Bbh.BlzFixtures

  alias Bbh.Blz

  setup :register_and_log_in_admin

  setup do
    {:ok, table} = Blz.parse_bundesbank(bundesbank_csv([sample_row(), other_row()]))
    :ok = Blz.import(table)
    on_exit(fn -> :ok = Blz.reset() end)
  end

  defp upload(lv, csv) do
    lv
    |> file_input("#blz-upload-form", :csv, [
      %{name: "blz-aktuell-csv-data.csv", content: csv, type: "text/csv"}
    ])
    |> render_upload("blz-aktuell-csv-data.csv")
  end

  test "shows the active table and links the Bundesbank download page", %{conn: conn} do
    {:ok, _lv, html} = live(conn, ~p"/admin/bankleitzahlen")

    assert html =~ "hochgeladene Tabelle"
    assert html =~ Blz.download_page()
  end

  test "previews the changes and applies them", %{conn: conn} do
    {:ok, lv, _html} = live(conn, ~p"/admin/bankleitzahlen")

    csv =
      bundesbank_csv([
        {"30000000", "1", "Testbank neu", "TESTDEFFXXX"},
        {"50000000", "1", "Neubank", "NEUBDEFFXXX"}
      ])

    html = upload(lv, csv)
    assert html =~ "1 neu"
    assert html =~ "1 geändert"
    assert html =~ "1 entfallen"
    assert has_element?(lv, "#blz-added", "Neubank")
    assert has_element?(lv, "#blz-removed", "Andere Bank")
    assert has_element?(lv, "#blz-changed del", "Testbank")

    # Nothing changes before the admin confirms.
    assert :error = Blz.lookup_by_iban("DE00 5000 0000 0000 0000 00")

    lv |> element("#blz-apply") |> render_click()
    assert render(lv) =~ "2 Bankleitzahlen übernommen"
    refute has_element?(lv, "#blz-preview")
    assert {:ok, %{name: "Neubank"}} = Blz.lookup_by_iban("DE00 5000 0000 0000 0000 00")
  end

  test "discarding a preview keeps the table", %{conn: conn} do
    {:ok, lv, _html} = live(conn, ~p"/admin/bankleitzahlen")

    upload(lv, bundesbank_csv([{"50000000", "1", "Neubank", "NEUBDEFFXXX"}, sample_row()]))
    lv |> element("#blz-discard") |> render_click()

    refute has_element?(lv, "#blz-preview")
    assert :error = Blz.lookup_by_iban("DE00 5000 0000 0000 0000 00")
  end

  test "an identical file cannot be applied", %{conn: conn} do
    {:ok, lv, _html} = live(conn, ~p"/admin/bankleitzahlen")

    assert upload(lv, bundesbank_csv([sample_row(), other_row()])) =~ "Keine Änderungen"
    assert has_element?(lv, "#blz-apply[disabled]")
  end

  test "rejects a file that is not the Bundesbank table", %{conn: conn} do
    {:ok, lv, _html} = live(conn, ~p"/admin/bankleitzahlen")

    assert upload(lv, "Name;Wert\nfoo;bar\n") =~ "nicht nach der Bankleitzahlendatei"
    refute has_element?(lv, "#blz-preview")
  end

  test "removing the upload falls back to the shipped table", %{conn: conn} do
    {:ok, lv, _html} = live(conn, ~p"/admin/bankleitzahlen")

    lv |> element("#blz-reset") |> render_click()

    assert render(lv) =~ "mitgelieferte Tabelle"
    refute has_element?(lv, "#blz-reset")
    assert {:ok, %{bic: "WELADED1MST"}} = Blz.lookup_by_iban("DE00 4005 0150 0000 0000 00")
  end
end
