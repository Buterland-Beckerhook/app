defmodule Bbh.Workers.EventPublishNotifierTest do
  use Bbh.DataCase, async: true

  import Bbh.CalendarFixtures

  alias Bbh.Calendar
  alias Bbh.Calendar.Event
  alias Bbh.Workers.EventPublishNotifier

  defp from_now(n), do: Bbh.Time.now() |> DateTime.add(n, :day) |> DateTime.truncate(:second)

  describe "with quiet hours off" do
    setup do
      {:ok, _} = Bbh.Settings.update(%{"quiet_hours_enabled" => false})
      :ok
    end

    test "only public, published, upcoming, unnotified events are pending" do
      due = event_fixture(status: "published", starts_at: from_now(3))
      _past = event_fixture(status: "published", starts_at: from_now(-1))
      _draft = event_fixture(status: "draft", starts_at: from_now(3))
      _internal = event_fixture(calendar: "vorstand", starts_at: from_now(3))

      assert Enum.map(Calendar.events_pending_notification(), & &1.id) == [due.id]
    end

    test "perform notifies each pending event once and marks it" do
      due = event_fixture(status: "published", starts_at: from_now(3))

      assert :ok = EventPublishNotifier.perform(%Oban.Job{})
      assert Repo.get(Event, due.id).notified_at

      # Marked, so no longer pending; a second run is a no-op.
      assert Calendar.events_pending_notification() == []
      assert :ok = EventPublishNotifier.perform(%Oban.Job{})
    end
  end

  test "quiet hours hold back the push, leaving the event unmarked for a later tick" do
    # A two-hour window starting at the current hour reliably covers "now".
    hour = Bbh.Time.now().hour

    {:ok, _} =
      Bbh.Settings.update(%{
        "quiet_hours_enabled" => true,
        "quiet_hours_start" => hour,
        "quiet_hours_end" => rem(hour + 2, 24)
      })

    due = event_fixture(status: "published", starts_at: from_now(3))

    assert :ok = EventPublishNotifier.perform(%Oban.Job{})
    refute Repo.get(Event, due.id).notified_at
  end
end
