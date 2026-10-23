defmodule Bbh.Analytics.IcalClient do
  @moduledoc """
  Coarse calendar-client family for a feed retrieval, derived from the User-Agent.

  Only the family key is stored (never the raw User-Agent), so the analytics stay as
  PII-free as before. Keys are stable strings; `label/1` turns one into German UI text.

  Caveat for reading the numbers: Google Calendar and Outlook.com poll server-side —
  one fetcher serves many users — so for those families a "client" is a server, not a
  person.
  """

  # Order matters: the first match wins. Microsoft goes first because the Outlook
  # apps embed the OS ("Outlook-iOS/…"); Thunderbird sends a Gecko UA, so it must be
  # tested before the generic browser rule.
  @rules [
    {"microsoft", ~r/Outlook|Microsoft|Exchange|MSOffice/i},
    {"apple", ~r/dataaccessd|CalendarAgent|iCal\/|macOS\/|iOS\/|iPadOS\//i},
    {"google", ~r/Google-Calendar/i},
    {"thunderbird", ~r/Thunderbird/i},
    {"davx5", ~r/DAVx5|DAVdroid|ICSx5|ICSdroid/i},
    {"browser", ~r/^Mozilla\//}
  ]

  @labels %{
    "apple" => "Apple Kalender",
    "google" => "Google Kalender",
    "microsoft" => "Outlook / Microsoft",
    "thunderbird" => "Thunderbird",
    "davx5" => "DAVx⁵ / ICSx⁵ (Android)",
    "browser" => "Webbrowser",
    "other" => "Sonstige",
    "unknown" => "Unbekannt"
  }

  @doc """
  The client family for a User-Agent string.

      iex> Bbh.Analytics.IcalClient.classify("iOS/18.1 (22B83) dataaccessd/1.0")
      "apple"

      iex> Bbh.Analytics.IcalClient.classify("Google-Calendar-Importer")
      "google"

      iex> Bbh.Analytics.IcalClient.classify(nil)
      "other"
  """
  def classify(ua) when is_binary(ua) and ua != "" do
    Enum.find_value(@rules, "other", fn {key, re} -> if Regex.match?(re, ua), do: key end)
  end

  def classify(_), do: "other"

  @doc """
  German display label for a family key. `nil` — rows recorded before the family was
  stored — is "Unbekannt".
  """
  def label(nil), do: @labels["unknown"]
  def label(key), do: Map.get(@labels, key, @labels["other"])
end
