defmodule Bbh.MembershipTest do
  use ExUnit.Case, async: true

  import Swoosh.TestAssertions

  alias Bbh.Membership

  @valid %{
    "nachname" => "  Mustermann  ",
    "vorname" => "  Max  ",
    "plz" => " 48599 ",
    "ort" => " Gronau ",
    "strasse" => " Musterweg 1 ",
    "geburtsdatum" => "1990-05-01",
    "email" => " max@example.com ",
    "kontoinhaber" => " Max Mustermann ",
    "iban" => " de89 3704 0044 0532 0130 00 ",
    "bic" => " cobadeffxxx ",
    "kreditinstitut" => " Commerzbank ",
    "sepa" => "true",
    "satzung" => "true",
    "datenspeicherung" => "true",
    "privacy" => "true"
  }

  describe "validate/1" do
    test "accepts valid params, trims and normalizes IBAN/BIC" do
      assert {:ok, data} = Membership.validate(@valid)
      assert data.nachname == "Mustermann"
      assert data.vorname == "Max"
      assert data.plz == "48599"
      assert data.ort == "Gronau"
      assert data.iban == "DE89370400440532013000"
      assert data.bic == "COBADEFFXXX"
      assert data.children == []
      assert data.sepa and data.satzung and data.datenspeicherung and data.privacy
    end

    test "accepts alternative consent truthy values" do
      assert {:ok, _} = Membership.validate(%{@valid | "sepa" => "on", "privacy" => "1"})
    end

    test "collects all non-empty children rows without a cap" do
      params =
        Map.merge(@valid, %{
          "kind_vorname" => ["Lisa", "", "Tom", "Mia"],
          "kind_geburtsdatum" => ["2015-01-01", "", "2018-03-03", "2020-07-07"]
        })

      assert {:ok, data} = Membership.validate(params)

      assert data.children == [
               %{vorname: "Lisa", geburtsdatum: "2015-01-01"},
               %{vorname: "Tom", geburtsdatum: "2018-03-03"},
               %{vorname: "Mia", geburtsdatum: "2020-07-07"}
             ]
    end

    test "derives an empty BIC/Kreditinstitut from the IBAN's Bankleitzahl" do
      # DE89370400440532013000 → BLZ 37040044 → Commerzbank / COBADEFFXXX.
      params = @valid |> Map.delete("bic") |> Map.delete("kreditinstitut")
      assert {:ok, data} = Membership.validate(params)
      assert data.bic == "COBADEFFXXX"
      assert data.kreditinstitut =~ "Commerzbank"
    end

    test "keeps an applicant-entered BIC/Kreditinstitut over the derived one" do
      params = %{@valid | "bic" => "MARKDEF1100", "kreditinstitut" => "Meine Bank"}
      assert {:ok, data} = Membership.validate(params)
      assert data.bic == "MARKDEF1100"
      assert data.kreditinstitut == "Meine Bank"
    end

    test "requires the personal fields" do
      assert {:error, errors} =
               Membership.validate(%{
                 @valid
                 | "nachname" => "  ",
                   "vorname" => "",
                   "plz" => "",
                   "ort" => "",
                   "strasse" => "",
                   "geburtsdatum" => "",
                   "email" => "nope"
               })

      for key <- [:nachname, :vorname, :plz, :ort, :strasse, :geburtsdatum, :email] do
        assert Map.has_key?(errors, key)
      end
    end

    test "rejects an invalid IBAN (bad check digits)" do
      assert {:error, %{iban: _}} =
               Membership.validate(%{@valid | "iban" => "DE89370400440532013001"})
    end

    test "rejects a malformed IBAN" do
      assert {:error, %{iban: _}} = Membership.validate(%{@valid | "iban" => "not-an-iban"})
    end

    test "rejects an invalid BIC" do
      assert {:error, %{bic: _}} = Membership.validate(%{@valid | "bic" => "123"})
    end

    test "requires all consents" do
      assert {:error, %{sepa: _}} = Membership.validate(Map.delete(@valid, "sepa"))
      assert {:error, %{satzung: _}} = Membership.validate(Map.delete(@valid, "satzung"))

      assert {:error, %{datenspeicherung: _}} =
               Membership.validate(Map.delete(@valid, "datenspeicherung"))

      assert {:error, %{privacy: _}} = Membership.validate(Map.delete(@valid, "privacy"))
    end

    test "the age thresholds never reject a submission (soft, hint-only)" do
      # A 5-year-old applicant with a 20-year-old \"child\" — both out of range — still valid.
      young = Date.utc_today() |> Date.add(-5 * 365) |> Date.to_iso8601()
      old = Date.utc_today() |> Date.add(-20 * 365) |> Date.to_iso8601()

      params =
        Map.merge(@valid, %{
          "geburtsdatum" => young,
          "kind_vorname" => ["Opa"],
          "kind_geburtsdatum" => [old]
        })

      assert {:ok, _} = Membership.validate(params)
    end
  end

  describe "deliver/1" do
    test "sends the application to the club and a confirmation copy to the applicant" do
      {:ok, data} = Membership.validate(@valid)
      assert {:ok, _} = Membership.deliver(data)

      # First mail: to the club inbox, with the applicant as reply-to.
      assert_email_sent(fn email ->
        assert email.subject =~ "Max Mustermann"
        assert email.reply_to == {"Max Mustermann", "max@example.com"}
        assert email.text_body =~ "DE89370400440532013000"
        assert email.text_body =~ "SEPA-Mandat erteilt:        ja"
      end)

      # Second mail: the copy to the applicant.
      assert_email_sent(fn email ->
        assert email.to == [{"Max Mustermann", "max@example.com"}]
        assert email.text_body =~ "vielen Dank"
      end)
    end

    test "the club mail flags an applicant below the minimum age" do
      young = Date.utc_today() |> Date.add(-5 * 365) |> Date.to_iso8601()
      {:ok, data} = Membership.validate(%{@valid | "geburtsdatum" => young})
      assert {:ok, _} = Membership.deliver(data)

      assert_email_sent(fn email ->
        assert email.subject =~ "Max Mustermann"
        assert email.text_body =~ "Mindestalter"
      end)
    end
  end
end
