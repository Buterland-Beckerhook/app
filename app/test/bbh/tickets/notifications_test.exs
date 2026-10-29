defmodule Bbh.Tickets.NotificationsTest do
  use Bbh.DataCase, async: false
  use Oban.Testing, repo: Bbh.Repo

  import Swoosh.TestAssertions
  import Bbh.AccountsFixtures
  import Bbh.TicketsFixtures

  alias Bbh.Settings
  alias Bbh.Tickets
  alias Bbh.Tickets.{Reminders, Ticket}
  alias Bbh.Workers.{TicketAssignedNotifier, TicketNewNotifier, TicketReminder}

  defp age(ticket, fields) do
    Repo.update_all(from(t in Ticket, where: t.id == ^ticket.id), set: fields)
    Repo.get!(Ticket, ticket.id)
  end

  # Fixtures send login mails; drop them so the assertions see only the worker's.
  defp flush_emails do
    receive do
      {:email, _} -> flush_emails()
    after
      0 -> :ok
    end
  end

  defp sent_emails(acc \\ []) do
    receive do
      {:email, email} -> sent_emails([email | acc])
    after
      0 -> Enum.reverse(acc)
    end
  end

  defp run(worker) do
    flush_emails()
    worker.perform(%Oban.Job{})
  end

  defp ago(amount, unit), do: DateTime.utc_now(:second) |> DateTime.add(-amount, unit)

  defp refute_personal_data(email) do
    refute email.subject =~ ~r/Schützenfest|Erika|erika@/
    refute email.text_body =~ ~r/Schützenfest|Erika|erika@/
  end

  setup do
    user = user_fixture()
    %{user: user, scope: granted_scope(user, ["info"])}
  end

  describe "new tickets" do
    test "wait two minutes, then go out bundled, once", %{user: user} do
      a = ticket_fixture()
      b = ticket_fixture()

      run(TicketNewNotifier)
      assert_no_email_sent()

      age(a, inserted_at: ago(3, :minute))
      age(b, inserted_at: ago(3, :minute))
      run(TicketNewNotifier)

      assert_email_sent(fn email ->
        refute_personal_data(email)
        assert email.subject == "Postfach: 2 neue Anfragen"
        assert email.text_body =~ Ticket.reference(a)
        assert email.text_body =~ Ticket.reference(b)
        assert email.to == [{"", user.email}]
      end)

      run(TicketNewNotifier)
      assert_no_email_sent()
    end

    test "only to users granted the queue; never spam", %{scope: scope} do
      other = user_fixture()
      granted_scope(other, ["vorstand"])

      {:ok, spam} = Tickets.mark_spam(scope, ticket_fixture())
      age(spam, inserted_at: ago(3, :minute))
      vorstand = ticket_fixture(queue: "vorstand") |> age(inserted_at: ago(3, :minute))

      run(TicketNewNotifier)

      assert_email_sent(fn email ->
        assert email.to == [{"", other.email}]
        assert email.subject == "Postfach: neue Anfrage (Vorstand)"
        assert email.text_body =~ Ticket.reference(vorstand)
      end)

      assert_no_email_sent()
    end

    test "a ticket moved to another queue is news there", %{scope: scope} do
      other = user_fixture()
      granted_scope(other, ["vorstand"])
      ticket = ticket_fixture() |> age(inserted_at: ago(3, :minute), notified_at: ago(1, :minute))
      {:ok, ticket} = Tickets.take(scope, ticket)

      {:ok, moved} = Tickets.move_queue(scope, ticket, "vorstand")
      assert %{status: "new", notified_at: nil} = moved

      run(TicketNewNotifier)
      assert_email_sent(fn email -> assert email.to == [{"", other.email}] end)
    end
  end

  test "a queue nobody is granted goes to the admins" do
    admin = admin_user_fixture()
    ticket = ticket_fixture(queue: "webmaster") |> age(inserted_at: ago(3, :minute))

    emails = run(TicketNewNotifier) && sent_emails()
    admins = Repo.all(from u in Bbh.Accounts.User, where: u.role == "admin", select: u.email)
    assert admin.email in admins
    assert Enum.sort(Enum.map(emails, fn %{to: [{_, to}]} -> to end)) == Enum.sort(admins)
    assert Enum.all?(emails, &(&1.text_body =~ Ticket.reference(ticket)))
  end

  describe "assignment" do
    test "someone else assigning tells the assignee", %{scope: scope, user: user} do
      colleague = user_fixture()
      granted_scope(colleague, ["info"])
      ticket = ticket_fixture()

      {:ok, _} = Tickets.assign(scope, ticket, colleague.id)

      assert_enqueued(
        worker: TicketAssignedNotifier,
        args: %{ticket_id: ticket.id, assignee_id: colleague.id, by_id: user.id}
      )

      [job] = all_enqueued(worker: TicketAssignedNotifier)
      flush_emails()
      assert :ok = perform_job(TicketAssignedNotifier, job.args)

      assert_email_sent(fn email ->
        refute_personal_data(email)
        assert email.to == [{"", colleague.email}]
        assert email.subject =~ "wurde dir zugewiesen"
      end)
    end

    test "taking it yourself sends nothing", %{scope: scope} do
      {:ok, _} = Tickets.take(scope, ticket_fixture())
      refute_enqueued(worker: TicketAssignedNotifier)
    end
  end

  describe "reminders" do
    setup do
      {:ok, _} = Settings.update_tickets(%{ticket_reminder_hour: 0})
      :ok
    end

    test "the overdue rules", %{scope: scope, user: user} do
      s = Settings.get()
      fresh = ticket_fixture()
      unassigned = ticket_fixture() |> age(inserted_at: ago(25, :hour))
      {:ok, idle} = Tickets.take(scope, ticket_fixture())
      idle = age(idle, last_activity_at: ago(8, :day))
      {:ok, waiting} = Tickets.set_status(scope, ticket_fixture(), "waiting")
      waiting = age(waiting, last_activity_at: ago(15, :day))

      {:ok, due} =
        Tickets.set_status(scope, ticket_fixture(), "follow_up", Date.add(Date.utc_today(), -1))

      {:ok, later} =
        Tickets.set_status(scope, ticket_fixture(), "follow_up", Date.add(Date.utc_today(), 5))

      overdue = Ticket |> Reminders.overdue(s) |> Repo.all() |> Enum.map(& &1.id)
      assert Enum.sort(overdue) == Enum.sort([unassigned.id, idle.id, waiting.id, due.id])
      refute fresh.id in overdue
      refute later.id in overdue

      # The list's tab uses the same rules.
      assert Tickets.list_tickets(scope, view: "overdue").total == 4

      # Everything goes to this user: granted the queue, and assignee of `idle`. Tickets
      # without an assignee (waiting, follow-up set by hand) go to the queue.
      assert %{} = due = Reminders.due(s)
      assert Map.keys(due) == [user.id]
      assert length(due[user.id]) == 4
    end

    test "go out once a day, from the configured hour", %{scope: scope, user: user} do
      ticket_fixture() |> age(inserted_at: ago(25, :hour))
      {:ok, _} = Tickets.take(scope, ticket_fixture() |> age(inserted_at: ago(25, :hour)))

      run(TicketReminder)

      assert_email_sent(fn email ->
        refute_personal_data(email)
        assert email.to == [{"", user.email}]
        assert email.subject == "Postfach: eine Anfrage wartet"
        assert email.text_body =~ "niemandem zugewiesen"
      end)

      run(TicketReminder)
      assert_no_email_sent()
    end

    test "not before the configured hour" do
      {:ok, _} = Settings.update_tickets(%{ticket_reminder_hour: 23})
      ticket_fixture() |> age(inserted_at: ago(25, :hour))

      if Bbh.Time.real_now().hour < 23 do
        run(TicketReminder)
        assert_no_email_sent()
        assert Settings.get().ticket_reminders_sent_on == nil
      end
    end

    test "admins get the digest with escalations; skipped when nothing is overdue" do
      admin = admin_user_fixture()
      escalated = ticket_fixture(queue: "vorstand") |> age(inserted_at: ago(4, :day))

      run(TicketReminder)

      # The unstaffed queue also reminds the admins; here only the digest matters.
      emails = Enum.filter(sent_emails(), &(&1.subject == "Postfach: Tagesübersicht"))
      admins = Repo.all(from u in Bbh.Accounts.User, where: u.role == "admin", select: u.email)
      assert admin.email in admins
      assert Enum.sort(Enum.map(emails, fn %{to: [{_, to}]} -> to end)) == Enum.sort(admins)

      for email <- emails do
        refute_personal_data(email)
        assert email.subject == "Postfach: Tagesübersicht"
        assert email.text_body =~ "Seit Tagen niemandem zugewiesen"
        assert email.text_body =~ Ticket.reference(escalated)
        assert email.text_body =~ "Vorstand: 1 Neu"
      end
    end

    test "no digest on a quiet day, nor when switched off" do
      admin_user_fixture()
      run(TicketReminder)
      assert_no_email_sent()

      Repo.update_all(Bbh.Settings.SiteSettings, set: [ticket_reminders_sent_on: nil])
      {:ok, _} = Settings.update_tickets(%{ticket_admin_digest_enabled: false})
      ticket_fixture(queue: "vorstand") |> age(inserted_at: ago(4, :day))
      run(TicketReminder)
      refute Enum.any?(sent_emails(), &(&1.subject == "Postfach: Tagesübersicht"))
    end
  end
end
