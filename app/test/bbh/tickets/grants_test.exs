defmodule Bbh.Tickets.GrantsTest do
  use Bbh.DataCase, async: true

  import Bbh.AccountsFixtures

  alias Bbh.Tickets.{Grant, Grants}

  setup do
    %{admin: admin_user_fixture(), user: user_fixture()}
  end

  test "set_grants replaces all of a user's grants and records the admin", %{
    admin: admin,
    user: user
  } do
    assert {:ok, ["info", "vorstand"]} = Grants.set_grants(admin, user, ["vorstand", "info", ""])

    assert {:ok, ["vorstand", "mitgliedschaft"]} =
             Grants.set_grants(admin, user, ["vorstand", "mitgliedschaft"])

    assert Grants.list_queue_keys(user) == ["vorstand", "mitgliedschaft"]
    assert Repo.get_by!(Grant, user_id: user.id, queue_key: "vorstand").granted_by_id == admin.id
    assert {:ok, []} = Grants.set_grants(admin, user, [])
  end

  test "refuses an unknown queue and leaves the grants as they were", %{admin: admin, user: user} do
    {:ok, _} = Grants.set_grants(admin, user, ["info"])
    assert Grants.set_grants(admin, user, ["info", "kegelclub"]) == {:error, :invalid_queue}
    assert Grants.list_queue_keys(user) == ["info"]
  end

  test "list_users and grants_by_user", %{admin: admin, user: user} do
    other = user_fixture()
    {:ok, _} = Grants.set_grants(admin, user, ["info"])
    {:ok, _} = Grants.set_grants(admin, other, ["info", "vorstand"])

    assert Enum.map(Grants.list_users("info"), & &1.id) |> Enum.sort() ==
             Enum.sort([user.id, other.id])

    assert Grants.list_users("webmaster") == []
    assert Enum.sort(Grants.grants_by_user()[other.id]) == ["info", "vorstand"]
  end

  test "grants go with the user", %{admin: admin, user: user} do
    {:ok, _} = Grants.set_grants(admin, user, ["info"])
    Bbh.Accounts.delete_user(user)
    assert Repo.aggregate(Grant, :count) == 0
  end

  test "the scope carries the grants", %{admin: admin, user: user} do
    {:ok, _} = Grants.set_grants(admin, user, ["offiziere"])
    assert Bbh.Accounts.Scope.for_user(user).ticket_queues == ["offiziere"]
  end
end
