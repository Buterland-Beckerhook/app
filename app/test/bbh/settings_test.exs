defmodule Bbh.SettingsTest do
  use Bbh.DataCase, async: true

  alias Bbh.Settings

  # A DateTime at the given local hour (only the hour matters to quiet_now?/1).
  defp at_hour(h), do: DateTime.new!(~D[2026-07-27], Time.new!(h, 0, 0), "Etc/UTC")

  describe "get/0 and update/1" do
    test "returns the seeded singleton with defaults" do
      settings = Settings.get()
      assert settings.quiet_hours_enabled
      assert settings.quiet_hours_start == 22
      assert settings.quiet_hours_end == 8
      refute settings.home_notice_enabled
    end

    test "update/1 persists changes to the singleton (still one row)" do
      {:ok, _} = Settings.update(%{"home_notice_enabled" => true, "home_notice_text" => "Hallo"})

      settings = Settings.get()
      assert settings.home_notice_enabled
      assert settings.home_notice_text == "Hallo"
      assert Repo.aggregate(Bbh.Settings.SiteSettings, :count) == 1
    end

    test "rejects an out-of-range hour" do
      {:error, changeset} = Settings.update(%{"quiet_hours_start" => 25})
      refute changeset.valid?
    end
  end

  describe "quiet_now?/1" do
    test "wrapping window (22 → 8) covers late night and early morning" do
      assert Settings.quiet_now?(at_hour(23))
      assert Settings.quiet_now?(at_hour(3))
      assert Settings.quiet_now?(at_hour(22))
      refute Settings.quiet_now?(at_hour(8))
      refute Settings.quiet_now?(at_hour(12))
    end

    test "non-wrapping window (1 → 6)" do
      {:ok, _} = Settings.update(%{"quiet_hours_start" => 1, "quiet_hours_end" => 6})
      assert Settings.quiet_now?(at_hour(3))
      refute Settings.quiet_now?(at_hour(0))
      refute Settings.quiet_now?(at_hour(6))
    end

    test "disabled window is never quiet" do
      {:ok, _} = Settings.update(%{"quiet_hours_enabled" => false})
      refute Settings.quiet_now?(at_hour(23))
    end
  end
end
