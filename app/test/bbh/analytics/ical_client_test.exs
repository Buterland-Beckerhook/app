defmodule Bbh.Analytics.IcalClientTest do
  use ExUnit.Case, async: true

  alias Bbh.Analytics.IcalClient

  doctest IcalClient

  describe "classify/1" do
    test "recognises the common calendar clients" do
      for {ua, family} <- [
            {"iOS/18.1 (22B83) dataaccessd/1.0", "apple"},
            {"macOS/15.1 (24B83) CalendarAgent/1000", "apple"},
            {"Google-Calendar-Importer", "google"},
            {"Microsoft Office/16.0 (Windows NT 10.0; Microsoft Outlook 16.0.17928)",
             "microsoft"},
            {"Outlook-iOS/2.0", "microsoft"},
            {"Mozilla/5.0 (X11; Linux x86_64; rv:128.0) Gecko/20100101 Thunderbird/128.4",
             "thunderbird"},
            {"ICSx5/2.3 (ical4j/3.2; Android)", "davx5"},
            {"DAVx5/4.4.3-ose (2024/10/01; dav4jvm; okhttp/4.12.0) Android/14", "davx5"},
            {"Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 Chrome/130",
             "browser"},
            {"SomethingElse/1.0", "other"},
            {"", "other"}
          ] do
        assert IcalClient.classify(ua) == family, "#{inspect(ua)} → #{family}"
      end
    end
  end

  describe "label/1" do
    test "nil (rows from before the column existed) is Unbekannt" do
      assert IcalClient.label(nil) == "Unbekannt"
    end

    test "an unexpected key falls back to Sonstige" do
      assert IcalClient.label("nope") == "Sonstige"
    end
  end
end
