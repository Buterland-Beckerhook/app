defmodule BbhWeb.Workers.UserDeleterTest do
  use Bbh.DataCase, async: true

  import Bbh.AccountsFixtures

  alias Bbh.Accounts
  alias Bbh.Accounts.User
  alias BbhWeb.Workers.UserDeleter

  # Bypasses the future-date validation: a date that has come by now.
  defp due_on(user, date), do: user |> Ecto.Changeset.change(delete_on: date) |> Repo.update!()

  test "deletes the users whose date has come and keeps the others" do
    today = Accounts.local_today()
    due = user_fixture() |> due_on(today)
    overdue = user_fixture() |> due_on(Date.add(today, -3))
    later = user_fixture() |> due_on(Date.add(today, 1))
    kept = user_fixture()

    assert :ok = UserDeleter.perform(%Oban.Job{})

    ids = Repo.all(from u in User, select: u.id)
    refute due.id in ids
    refute overdue.id in ids
    assert later.id in ids
    assert kept.id in ids
  end

  test "never deletes the last admin" do
    admin = admin_user_fixture() |> due_on(Accounts.local_today())

    assert :ok = UserDeleter.perform(%Oban.Job{})

    assert Accounts.get_user!(admin.id)
  end
end
