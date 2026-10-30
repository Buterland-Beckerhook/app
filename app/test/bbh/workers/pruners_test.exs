defmodule Bbh.Workers.PrunersTest do
  use Bbh.DataCase, async: true

  import Bbh.AccountsFixtures

  alias Bbh.Accounts.{AuthEvent, AuthLog}
  alias Bbh.Redirects.NotFoundPath
  alias Bbh.Workers.{AuthPruner, NotFoundPruner, TicketPruner}

  defp days_ago(days), do: DateTime.utc_now(:second) |> DateTime.add(-days, :day)

  test "NotFoundPruner drops 404 paths not requested for 90 days" do
    for {path, seen} <- [{"/alt", days_ago(91)}, {"/frisch", days_ago(1)}] do
      Repo.insert!(%NotFoundPath{path: path, first_seen_at: seen, last_seen_at: seen})
    end

    assert :ok = NotFoundPruner.perform(%Oban.Job{})
    assert Repo.all(from n in NotFoundPath, select: n.path) == ["/frisch"]
  end

  test "AuthPruner drops login-log entries past their retention" do
    user = user_fixture()

    for _ <- 1..2 do
      AuthLog.record(%{
        user: user,
        event: "login_succeeded",
        method: "passkey",
        ip: "203.0.113.7"
      })
    end

    [old, recent] = Repo.all(AuthEvent)

    old
    |> Ecto.Changeset.change(inserted_at: days_ago(AuthLog.retention_days() + 1))
    |> Repo.update!()

    assert :ok = AuthPruner.perform(%Oban.Job{})
    assert [%{id: id}] = Repo.all(AuthEvent)
    assert id == recent.id
  end

  test "TicketPruner runs the Postfach retention" do
    assert :ok = TicketPruner.perform(%Oban.Job{})
  end
end
