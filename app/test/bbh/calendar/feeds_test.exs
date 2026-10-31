defmodule Bbh.Calendar.FeedsTest do
  # async: false — turns on the node-global feed cache for the duration.
  use Bbh.DataCase, async: false

  import Bbh.CalendarFixtures

  alias Bbh.Calendar.Feeds

  @site "https://example.test"

  setup do
    previous = Application.fetch_env(:bbh, Feeds)
    Application.put_env(:bbh, Feeds, cache: true)

    on_exit(fn ->
      :persistent_term.erase({Feeds, :public})

      case previous do
        {:ok, value} -> Application.put_env(:bbh, Feeds, value)
        :error -> Application.delete_env(:bbh, Feeds)
      end
    end)

    :persistent_term.erase({Feeds, :public})
    :ok
  end

  test "serves the cached text until an event changes" do
    event = event_fixture(title: "Königsschießen")
    {etag, body} = Feeds.public(@site)
    assert body =~ "Königsschießen"
    assert {^etag, ^body} = Feeds.public(@site)

    # Push updated_at past the cached second, as a later save would.
    later = NaiveDateTime.add(event.updated_at, 5)

    Repo.update_all(from(e in Bbh.Calendar.Event, where: e.id == ^event.id),
      set: [title: "Schützenfest", updated_at: later]
    )

    {new_etag, new_body} = Feeds.public(@site)
    assert new_body =~ "Schützenfest"
    refute new_etag == etag
  end

  test "a deleted event leaves the feed" do
    event = event_fixture(title: "Königsschießen")
    {_, body} = Feeds.public(@site)
    assert body =~ "Königsschießen"

    Repo.delete!(event)
    {_, body} = Feeds.public(@site)
    refute body =~ "Königsschießen"
  end
end
