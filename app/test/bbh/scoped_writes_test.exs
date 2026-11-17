defmodule Bbh.ScopedWritesTest do
  @moduledoc """
  The contexts' create and update functions check the scope themselves, so a caller
  that forgets the LiveView's or MCP tool's check still cannot write past it.
  """
  use Bbh.DataCase, async: true

  import Bbh.CalendarFixtures
  import Bbh.ContentFixtures

  alias Bbh.Accounts.{Scope, User}
  alias Bbh.{Calendar, Club, Content, Media}

  defp scope(role, opts \\ []) do
    %Scope{
      user: %User{
        id: Ecto.UUID.generate(),
        role: role,
        auth_method: Keyword.get(opts, :auth_method, "passkey"),
        calendars: Keyword.get(opts, :calendars, [])
      }
    }
  end

  test "content writes need the section" do
    calendar_editor = scope("calendar_editor")

    assert Content.create_article(calendar_editor, %{title: "X"}) == {:error, :unauthorized}

    assert Content.update_article(nil, article_fixture(), %{title: "X"}) ==
             {:error, :unauthorized}

    assert Content.Pages.create_page(calendar_editor, %{title: "X"}) == {:error, :unauthorized}
    assert Club.create_person(calendar_editor, %{name: "X"}) == {:error, :unauthorized}
    assert Club.create_trophy(scope("tickets"), %{name: "X"}) == {:error, :unauthorized}

    assert Media.update_upload(calendar_editor, upload_fixture(), %{title: "X"}) ==
             {:error, :unauthorized}

    assert {:ok, _} =
             Content.create_article(scope("editor"), %{
               title: "Erlaubt",
               slug: "erlaubt",
               date_published: ~U[2030-01-01 10:00:00Z]
             })
  end

  test "an event needs its calendar; a programme item its festival's" do
    [internal | _] = Calendar.Event.calendars()
    granted = scope("calendar_editor", calendars: [internal])
    attrs = %{title: "Sitzung", slug: "sitzung", starts_at: ~U[2030-03-01 18:00:00Z]}

    # The public calendar is not theirs, an internal one they hold is.
    assert Calendar.create_event(granted, attrs) == {:error, :unauthorized}
    assert {:ok, event} = Calendar.create_event(granted, Map.put(attrs, :calendar, internal))

    # Moving it to the public calendar needs that one too.
    assert Calendar.update_event(granted, event, %{calendar: nil}) == {:error, :unauthorized}

    # A programme item of a public festival is public, whatever it claims itself.
    festival = event_fixture(%{title: "Fest"})

    assert Calendar.create_event(
             granted,
             Map.merge(attrs, %{parent_id: festival.id, calendar: internal})
           ) == {:error, :unauthorized}

    assert Calendar.delete_event(scope("editor"), event) == {:error, :unauthorized}
    assert Repo.get(Calendar.Event, event.id)
  end
end
