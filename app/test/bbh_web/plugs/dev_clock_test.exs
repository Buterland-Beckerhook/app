defmodule BbhWeb.Plugs.DevClockTest do
  # async: false — the plug writes the process dictionary key Bbh.Time reads.
  use BbhWeb.ConnCase, async: false

  alias BbhWeb.Plugs.DevClock

  # The plug is only wired into the endpoint in dev; here it is called directly. The
  # shift itself (Bbh.Time.now/1 reading the offset) is compiled out of the test env —
  # see Bbh.TimeTest for the arithmetic.

  setup do
    on_exit(fn -> Process.delete(Bbh.Time.offset_key()) end)
  end

  # A fresh request carrying over only the previous one's session.
  defp run(previous \\ nil, query) do
    session = if previous, do: get_session(previous), else: %{}

    %{build_conn() | query_string: query}
    |> init_test_session(session)
    |> DevClock.call([])
  end

  test "?jetzt= simulates that moment and remembers it in the session" do
    conn = run("jetzt=2026-07-19T09:25")

    assert conn.assigns.simulated_now == ~U[2026-07-19 09:25:00Z]
    refute conn.assigns.dev_clock_frame
    assert get_session(conn, "dev_clock_now") == "2026-07-19T09:25"

    offset = Process.get(Bbh.Time.offset_key())
    expected = DateTime.diff(~U[2026-07-19 09:25:00Z], Bbh.Time.real_now())
    assert_in_delta offset, expected, 2
  end

  test "falls back to the remembered moment, and ?jetzt= with no value forgets it" do
    remembered = run("jetzt=2026-07-19")
    assert remembered.assigns.simulated_now == ~U[2026-07-19 00:00:00Z]

    later = run(remembered, "")
    assert later.assigns.simulated_now == ~U[2026-07-19 00:00:00Z]

    cleared = run(later, "jetzt=")
    refute Map.has_key?(cleared.assigns, :simulated_now)
    assert get_session(cleared, "dev_clock_now") == nil
    assert Process.get(Bbh.Time.offset_key()) == nil
  end

  test "?jetzt_temp=1 simulates without touching the session" do
    conn = run("jetzt=2026-07-19T09:25&jetzt_temp=1")

    assert conn.assigns.simulated_now == ~U[2026-07-19 09:25:00Z]
    assert conn.assigns.dev_clock_frame
    assert get_session(conn, "dev_clock_now") == nil
  end

  test "clears an offset left behind by an earlier request on the same process" do
    Process.put(Bbh.Time.offset_key(), 12_345)

    conn = run("")

    refute Map.has_key?(conn.assigns, :simulated_now)
    assert Process.get(Bbh.Time.offset_key()) == nil
  end

  test "ignores a value it cannot parse" do
    conn = run("jetzt=morgen")

    refute Map.has_key?(conn.assigns, :simulated_now)
    assert get_session(conn, "dev_clock_now") == nil
  end

  describe "parse/1" do
    test "accepts a date, minutes or seconds" do
      assert DevClock.parse("2026-07-19") == {:ok, ~U[2026-07-19 00:00:00Z]}
      assert DevClock.parse("2026-07-19T09:25") == {:ok, ~U[2026-07-19 09:25:00Z]}
      assert DevClock.parse("2026-07-19T09:25:30") == {:ok, ~U[2026-07-19 09:25:30Z]}
      assert DevClock.parse("19.07.2026") == :error
      assert DevClock.parse(nil) == :error
    end
  end
end
