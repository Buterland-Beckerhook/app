defmodule Bbh.Notifications.Device do
  @moduledoc """
  Short human description of the browser behind a push subscription ("Firefox ·
  Android"), derived from the User-Agent of the subscribe request. Only this summary
  is stored, never the raw User-Agent.

  iPadOS Safari presents itself as macOS, so an iPad shows up as "Safari · macOS".
  """

  # First match wins: Edge, Opera and Samsung Internet all carry "Chrome/" (and
  # Chrome carries "Safari/"), so the more specific names come first.
  @browsers [
    {"Edge", ~r/Edg(e|A|iOS)?\//},
    {"Opera", ~r/OPR\/|Opera/},
    {"Samsung Internet", ~r/SamsungBrowser\//},
    {"Firefox", ~r/Firefox\/|FxiOS\//},
    {"Chrome", ~r/Chrome\/|CriOS\//},
    {"Safari", ~r/Safari\//}
  ]

  @systems [
    {"iOS", ~r/iPhone|iPod/},
    {"iPadOS", ~r/iPad/},
    {"Android", ~r/Android/},
    {"ChromeOS", ~r/CrOS/},
    {"Windows", ~r/Windows/},
    {"macOS", ~r/Macintosh|Mac OS X/},
    {"Linux", ~r/Linux/}
  ]

  @doc """
  Describe a User-Agent; `nil` when neither browser nor OS is recognised.

      iex> Bbh.Notifications.Device.describe(
      ...>   "Mozilla/5.0 (Android 14; Mobile; rv:131.0) Gecko/131.0 Firefox/131.0"
      ...> )
      "Firefox · Android"

      iex> Bbh.Notifications.Device.describe(nil)
      nil
  """
  def describe(ua) when is_binary(ua) and ua != "" do
    case {match(@browsers, ua), match(@systems, ua)} do
      {nil, nil} -> nil
      {browser, nil} -> browser
      {nil, os} -> os
      {browser, os} -> "#{browser} · #{os}"
    end
  end

  def describe(_), do: nil

  defp match(rules, ua) do
    Enum.find_value(rules, fn {name, re} -> if Regex.match?(re, ua), do: name end)
  end
end
