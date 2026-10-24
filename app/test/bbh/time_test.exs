defmodule Bbh.TimeTest do
  use ExUnit.Case, async: false

  alias Bbh.Time, as: BTime

  setup do
    previous = Application.get_env(:bbh, :time_zone)
    on_exit(fn -> Application.put_env(:bbh, :time_zone, previous) end)
    :ok
  end

  describe "time_zone/0" do
    test "returns the configured zone" do
      Application.put_env(:bbh, :time_zone, "Europe/Amsterdam")
      assert BTime.time_zone() == "Europe/Amsterdam"
    end

    test "defaults to Europe/Berlin when unset" do
      Application.delete_env(:bbh, :time_zone)
      assert BTime.time_zone() == "Europe/Berlin"
    end
  end

  describe "now/1" do
    test "returns local wall-clock components re-tagged as UTC" do
      # Sydney is comfortably offset from UTC year-round, so the wall-clock always
      # differs — no dependence on the current DST state of a European zone.
      Application.put_env(:bbh, :time_zone, "Australia/Sydney")

      now = BTime.now()
      utc = DateTime.utc_now()

      # Tagged UTC so it is a drop-in for DateTime.utc_now/1 and castable to :utc_datetime.
      assert now.time_zone == "Etc/UTC"
      # But the components are the Sydney wall-clock: hours ahead of real UTC.
      assert DateTime.diff(now, utc, :minute) > 0
    end

    test "truncates to the requested precision" do
      assert BTime.now(:second).microsecond == {0, 0}
    end

    test "ignores a dev-clock offset outside dev" do
      Process.put(BTime.offset_key(), 86_400)
      on_exit(fn -> Process.delete(BTime.offset_key()) end)

      assert_in_delta DateTime.to_unix(BTime.now()), DateTime.to_unix(BTime.real_now()), 2
    end
  end

  describe "apply_offset/2" do
    test "shifts by whole seconds, in both directions" do
      dt = ~U[2026-07-19 09:25:00Z]

      assert BTime.apply_offset(dt, 0) == dt
      assert BTime.apply_offset(dt, 300) == ~U[2026-07-19 09:30:00Z]
      assert BTime.apply_offset(dt, -86_400) == ~U[2026-07-18 09:25:00Z]
    end
  end
end
