defmodule Bbh.BlzTest do
  # The shipped priv/data/blz.tsv is loaded into persistent_term at app boot.
  use ExUnit.Case, async: true

  alias Bbh.Blz

  test "resolves a German IBAN to its BIC and bank name" do
    # BLZ 40050150 → Sparkasse Münsterland Ost / WELADED1MST. Check digits are
    # irrelevant to the lookup (it only reads the Bankleitzahl slice).
    assert {:ok, %{bic: "WELADED1MST", name: name}} =
             Blz.lookup_by_iban("DE00 4005 0150 0000 0000 00")

    assert name =~ "Sparkasse"
  end

  test "ignores spaces and lower case" do
    assert {:ok, %{bic: "COBADEFFXXX"}} = Blz.lookup_by_iban("de89 3704 0044 0532 0130 00")
  end

  test "returns :error for an unknown Bankleitzahl" do
    assert :error = Blz.lookup_by_iban("DE00 9999 9999 0000 0000 00")
  end

  test "returns :error for a non-German IBAN" do
    assert :error = Blz.lookup_by_iban("AT611904300234573201")
  end

  test "the table is non-empty (data file shipped and loaded)" do
    assert Blz.size() > 1000
  end
end
