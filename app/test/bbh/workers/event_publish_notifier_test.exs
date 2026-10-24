defmodule Bbh.Workers.EventPublishNotifierTest do
  use Bbh.DataCase, async: true

  import Bbh.CalendarFixtures

  alias Bbh.Calendar
  alias Bbh.Calendar.Event
  alias Bbh.Workers.EventPublishNotifier

  defp from_now(n), do: Bbh.Time.now() |> DateTime.add(n, :day) |> DateTime.truncate(:second)

  # Publishing "settles" 30 minutes after the last change to a pending event.
  defp settled, do: DateTime.add(DateTime.utc_now(), 31, :minute)
  defp unsettled, do: DateTime.add(DateTime.utc_now(), 29, :minute)

  defp notified?(event), do: not is_nil(Repo.get(Event, event.id).notified_at)

  describe "with quiet hours off" do
    setup do
      {:ok, _} = Bbh.Settings.update(%{"quiet_hours_enabled" => false})
      :ok
    end

    test "only public, published, upcoming, unnotified top-level events are pending" do
      due = event_fixture(status: "published", starts_at: from_now(3))
      _past = event_fixture(status: "published", starts_at: from_now(-1))
      _draft = event_fixture(status: "draft", starts_at: from_now(3))
      _internal = event_fixture(calendar: "vorstand", starts_at: from_now(3))

      assert Enum.map(Calendar.events_pending_notification(), & &1.id) == [due.id]
    end

    test "waits until publishing has settled, then marks the whole bundle at once" do
      a = event_fixture(status: "published", starts_at: from_now(3))
      b = event_fixture(status: "published", starts_at: from_now(30))

      assert EventPublishNotifier.deliver_pending(unsettled()) == :waiting
      refute notified?(a) or notified?(b)

      assert EventPublishNotifier.deliver_pending(settled()) == :sent
      assert notified?(a) and notified?(b)

      # Nothing left; a second run is a no-op.
      assert EventPublishNotifier.deliver_pending(settled()) == :none
    end

    test "a later edit to a pending event restarts the wait" do
      event = event_fixture(status: "published", starts_at: from_now(3))
      later = DateTime.add(DateTime.utc_now(), 20, :minute)

      Repo.update_all(Event, set: [updated_at: DateTime.truncate(later, :second)])

      assert EventPublishNotifier.deliver_pending(settled()) == :waiting
      refute notified?(event)
    end

    test "perform/1 runs on the real clock: a fresh event waits" do
      event = event_fixture(status: "published", starts_at: from_now(3))

      assert :ok = EventPublishNotifier.perform(%Oban.Job{})
      refute notified?(event)
    end
  end

  test "quiet hours hold back the bundle, leaving the events unmarked for a later tick" do
    # A two-hour window starting at the current hour reliably covers "now".
    hour = Bbh.Time.now().hour

    {:ok, _} =
      Bbh.Settings.update(%{
        "quiet_hours_enabled" => true,
        "quiet_hours_start" => hour,
        "quiet_hours_end" => rem(hour + 2, 24)
      })

    due = event_fixture(status: "published", starts_at: from_now(3))

    assert EventPublishNotifier.deliver_pending(settled()) == :waiting
    refute notified?(due)
  end

  describe "payload/1" do
    defp ev(title, year \\ 2027), do: %Event{title: title, year: year, slug: "x", parent_id: nil}

    test "one event: \"Neuer Termin\" with its title and link" do
      assert %{title: "Neuer Termin", body: "Frauenfest", url: url} =
               EventPublishNotifier.payload([ev("Frauenfest")])

      assert url =~ "/termine/2027/x"
    end

    test "several: a count, the first titles and the year's list" do
      events = Enum.map(~w(Biwak Frauenfest Schützenfest Winterfest Kuhfladenbingo), &ev/1)

      assert %{title: "5 neue Termine", body: body, url: url} =
               EventPublishNotifier.payload(events)

      assert body == "Biwak, Frauenfest, Schützenfest und 2 weitere"
      assert url =~ "/termine?jahr=2027"

      assert %{body: "Biwak, Winterfest", url: url} =
               EventPublishNotifier.payload([ev("Biwak"), ev("Winterfest", 2028)])

      assert String.ends_with?(url, "/termine")
    end
  end
end
