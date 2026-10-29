defmodule Bbh.Accounts.AuthLogTest do
  use Bbh.DataCase, async: true

  import Bbh.AccountsFixtures

  alias Bbh.Accounts.{AuthEvent, AuthLog}
  alias Bbh.Repo

  defp age(event, days) do
    at = DateTime.utc_now(:second) |> DateTime.add(-days, :day)
    event |> Ecto.Changeset.change(inserted_at: at) |> Repo.update!()
  end

  test "records an event for a user" do
    user = user_fixture()

    assert {:ok, event} =
             AuthLog.record(%{
               user: user,
               event: "login_succeeded",
               method: "passkey",
               ip: "203.0.113.7",
               user_agent: "Firefox"
             })

    assert event.user_id == user.id
    assert [%AuthEvent{event: "login_succeeded"}] = AuthLog.list_for_user(user)
  end

  test "records an attempt without a user" do
    assert {:ok, %AuthEvent{user_id: nil}} =
             AuthLog.record(%{user: nil, event: "login_failed", method: "magic_link"})
  end

  test "truncates the user agent" do
    {:ok, event} = AuthLog.record(%{event: "logged_out", user_agent: String.duplicate("a", 400)})
    assert String.length(event.user_agent) == 255
  end

  test "refuses unknown events and methods without raising" do
    assert AuthLog.record(%{event: "hacked"}) == :error
    assert AuthLog.record(%{event: "login_failed", method: "password"}) == :error
  end

  test "lists newest first and only within the retention period" do
    user = user_fixture()
    {:ok, old} = AuthLog.record(%{user: user, event: "login_succeeded"})
    age(old, 91)
    {:ok, earlier} = AuthLog.record(%{user: user, event: "magic_link_sent"})
    age(earlier, 1)
    {:ok, latest} = AuthLog.record(%{user: user, event: "login_succeeded"})

    assert Enum.map(AuthLog.list_for_user(user), & &1.id) == [latest.id, earlier.id]
  end

  test "prune deletes entries past the window" do
    {:ok, old} = AuthLog.record(%{event: "login_failed"})
    age(old, 91)
    {:ok, fresh} = AuthLog.record(%{event: "login_failed"})

    assert AuthLog.prune(90) == 1
    refute Repo.get(AuthEvent, old.id)
    assert Repo.get(AuthEvent, fresh.id)
  end

  test "entries go with the user" do
    user = user_fixture()
    {:ok, event} = AuthLog.record(%{user: user, event: "login_succeeded"})
    Bbh.Accounts.delete_user(user)
    refute Repo.get(AuthEvent, event.id)
  end
end
