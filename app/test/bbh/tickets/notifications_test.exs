defmodule Bbh.Tickets.NotificationsTest do
  use Bbh.DataCase, async: false
  use Oban.Testing, repo: Bbh.Repo

  import Swoosh.TestAssertions
  import Bbh.AccountsFixtures
  import Bbh.TicketsFixtures

  alias Bbh.Settings
  alias Bbh.Tickets
  alias Bbh.Tickets.{Alerts, Notification, Reminders, Ticket}
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
    # Outside the tests' concern, and they must not depend on the time they run at.
    {:ok, _} = Settings.update(%{quiet_hours_enabled: false})
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
        assert email.text_body =~ "Aus Datenschutzgründen"
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

  describe "slots" do
    setup do
      %{settings: %Bbh.Settings.SiteSettings{}}
    end

    test "count from the end of the quiet hours", %{settings: s} do
      assert Alerts.slots(2, s) == :always
      assert Alerts.slots(240, s) == [8 * 60, 12 * 60, 16 * 60, 20 * 60]
      assert Alerts.slots(480, s) == [8 * 60, 16 * 60]
      assert Alerts.slots(720, s) == [8 * 60, 20 * 60]
      assert Alerts.slots(120, s) == Enum.map(8..20//2, &(&1 * 60))
      assert Alerts.slots(60, s) == Enum.map(8..21, &(&1 * 60))
    end

    test "once a day is 19 o'clock, or the last active hour", %{settings: s} do
      assert Alerts.slots(1440, s) == [19 * 60]
      assert Alerts.slots(1440, %{s | quiet_hours_start: 18, quiet_hours_end: 6}) == [17 * 60]
    end

    test "without quiet hours the whole day counts", %{settings: s} do
      assert Alerts.slots(720, %{s | quiet_hours_enabled: false}) == [8 * 60, 20 * 60]
      assert Alerts.slots(1440, %{s | quiet_hours_enabled: false}) == [19 * 60]
    end
  end

  describe "fixed times" do
    # Local wall-clock on a winter day (Berlin = UTC+1), the way flush/1 takes it.
    defp local(hour, minute \\ 1) do
      DateTime.new!(~D[2026-11-04], Time.new!(hour, minute, 0), "Etc/UTC")
    end

    defp prefer(user, attrs) do
      {:ok, user} = Alerts.update_preferences(user, attrs)
      user
    end

    # A ticket that entered the outbox at `hour:minute` local time.
    defp pending(hour, minute \\ 0) do
      ticket = ticket_fixture() |> age(notified_at: ago(1, :minute))
      :ok = Alerts.enqueue_new([ticket])
      utc = local(hour, minute) |> DateTime.add(-1, :hour)

      Repo.update_all(from(n in Notification, where: n.ticket_id == ^ticket.id),
        set: [inserted_at: utc]
      )

      ticket
    end

    defp flush(hour, minute \\ 1) do
      flush_emails()
      Alerts.flush(local(hour, minute))
    end

    test "what arrived before a time goes out then, in one message", %{user: user} do
      prefer(user, %{ticket_notify_interval_minutes: 240})
      a = pending(9)
      b = pending(11, 30)
      later = pending(12, 30)

      flush(11, 59)
      assert_no_email_sent()

      flush(12)

      assert_email_sent(fn email ->
        assert email.subject == "Postfach: 2 neue Anfragen"
        assert email.text_body =~ Ticket.reference(a)
        assert email.text_body =~ Ticket.reference(b)
        refute email.text_body =~ Ticket.reference(later)
      end)

      flush(13)
      assert_no_email_sent()

      flush(16)
      assert_email_sent(fn email -> assert email.text_body =~ Ticket.reference(later) end)
      assert Repo.aggregate(Notification, :count) == 0
    end

    test "once a day goes out at 19 o'clock", %{user: user} do
      prefer(user, %{ticket_notify_interval_minutes: 1440})
      pending(9)

      flush(18, 59)
      assert_no_email_sent()

      flush(19)
      assert_email_sent(fn email -> assert email.subject =~ "neue Anfrage" end)
    end

    test "a request taken while collecting is not announced", %{user: user, scope: scope} do
      prefer(user, %{ticket_notify_interval_minutes: 240})
      {:ok, _} = Tickets.take(scope, pending(9))

      flush(12)
      assert_no_email_sent()
      assert Repo.aggregate(Notification, :count) == 0
    end

    test "replies are collected with new requests, without personal data", %{user: user} do
      prefer(user, %{ticket_notify_interval_minutes: 240})
      replied = ticket_fixture() |> age(status: "open", notified_at: ago(1, :hour))
      fresh = pending(9)

      {:ok, _} = Tickets.add_inbound(replied, %{body: "Danke!", from: "erika@example.com"})

      Repo.update_all(from(n in Notification, where: n.ticket_id == ^replied.id),
        set: [inserted_at: local(9) |> DateTime.add(-1, :hour)]
      )

      flush(12)

      assert_email_sent(fn email ->
        refute_personal_data(email)
        assert email.subject == "Postfach: 2 neue Eingänge"
        assert email.text_body =~ Ticket.reference(replied)
        assert email.text_body =~ Ticket.reference(fresh)
      end)
    end

    test "the night's requests and the reminders share the 8 o'clock message", %{user: user} do
      prefer(user, %{ticket_notify_interval_minutes: 240})
      {:ok, _} = Settings.update_tickets(%{ticket_reminder_hour: 8})
      waiting = ticket_fixture() |> age(inserted_at: ago(25, :hour), notified_at: ago(24, :hour))
      night = pending(3)

      flush(8)

      assert_email_sent(fn email ->
        assert email.subject == "Postfach: Neues und Wartendes"
        assert email.text_body =~ Ticket.reference(waiting)
        assert email.text_body =~ Ticket.reference(night)
      end)

      assert_no_email_sent()

      flush(12)
      assert_no_email_sent()
    end

    test "once a day stays one message, reminders included", %{user: user} do
      prefer(user, %{ticket_notify_interval_minutes: 1440})
      {:ok, _} = Settings.update_tickets(%{ticket_reminder_hour: 8})
      ticket_fixture() |> age(inserted_at: ago(25, :hour), notified_at: ago(24, :hour))

      flush(8)
      assert_no_email_sent()
      assert Repo.reload!(user).ticket_reminded_on == nil

      flush(19)
      assert_email_sent(fn email -> assert email.subject == "Postfach: eine Anfrage wartet" end)
    end

    test "only the offered intervals are accepted, so at least daily", %{user: user} do
      assert {:error, changeset} =
               Alerts.update_preferences(user, %{ticket_notify_interval_minutes: 2880})

      assert errors_on(changeset).ticket_notify_interval_minutes != []
    end
  end

  describe "quiet hours" do
    setup do
      hour = Bbh.Time.real_now().hour

      {:ok, _} =
        Settings.update(%{
          quiet_hours_enabled: true,
          quiet_hours_start: rem(hour + 23, 24),
          quiet_hours_end: rem(hour + 2, 24)
        })

      :ok
    end

    test "hold everything back, and it goes out afterwards" do
      ticket_fixture() |> age(inserted_at: ago(3, :minute))

      run(TicketNewNotifier)
      assert_no_email_sent()
      assert Repo.aggregate(Notification, :count) == 1

      {:ok, _} = Settings.update(%{quiet_hours_enabled: false})
      run(TicketNewNotifier)
      assert_email_sent(fn email -> assert email.subject =~ "neue Anfrage" end)
    end

    test "postpone an assignment", %{scope: scope} do
      colleague = user_fixture()
      granted_scope(colleague, ["info"])
      {:ok, _} = Tickets.assign(scope, ticket_fixture(), colleague.id)
      [job] = all_enqueued(worker: TicketAssignedNotifier)

      flush_emails()
      assert {:snooze, _} = perform_job(TicketAssignedNotifier, job.args)
      assert_no_email_sent()
    end

    test "postpone the reminders without using up the day" do
      {:ok, _} = Settings.update_tickets(%{ticket_reminder_hour: 0})
      user = user_fixture()
      granted_scope(user, ["info"])
      ticket_fixture() |> age(inserted_at: ago(25, :hour), notified_at: ago(24, :hour))

      run(TicketNewNotifier)
      run(TicketReminder)
      assert_no_email_sent()
      assert Settings.get().ticket_reminders_sent_on == nil
      assert Repo.reload!(user).ticket_reminded_on == nil
    end
  end

  describe "push" do
    setup do
      test_pid = self()
      previous = Application.get_env(:bbh, Bbh.Notifications, [])

      Application.put_env(
        :bbh,
        Bbh.Notifications,
        Keyword.put(previous, :sender, fn json, message ->
          send(test_pid, {:push, Jason.decode!(json)["endpoint"], Jason.decode!(message)})
          {:ok, :sent}
        end)
      )

      on_exit(fn -> Application.put_env(:bbh, Bbh.Notifications, previous) end)
      :ok
    end

    defp push_ticket, do: ticket_fixture() |> age(inserted_at: ago(3, :minute))

    defp device(user, name) do
      endpoint = "https://fcm.googleapis.com/fcm/send/#{name}"

      {:ok, _} =
        Bbh.Notifications.link_device(user, %{
          "endpoint" => endpoint,
          "keys" => %{"p256dh" => "pk", "auth" => "ak"}
        })

      endpoint
    end

    test "goes to all the user's devices instead of a mail", %{user: user} do
      {:ok, _} = Alerts.update_preferences(user, %{ticket_notify_channel: "push"})
      one = device(user, "one")
      two = device(user, "two")
      ticket = push_ticket()

      run(TicketNewNotifier)

      assert_received {:push, ^one, %{"body" => body, "url" => url}}
      assert_received {:push, ^two, _}
      assert body =~ Ticket.reference(ticket)
      refute body =~ ~r/Schützenfest|Erika/
      assert url =~ "/admin/postfach/#{Ticket.reference(ticket)}"
      assert_no_email_sent()
    end

    test "both channels send both", %{user: user} do
      {:ok, _} = Alerts.update_preferences(user, %{ticket_notify_channel: "both"})
      one = device(user, "one")
      push_ticket()

      run(TicketNewNotifier)

      assert_received {:push, ^one, _}
      assert_email_sent(fn email -> assert email.subject =~ "neue Anfrage" end)
    end

    test "no device means a mail, so nothing is lost", %{user: user} do
      {:ok, _} = Alerts.update_preferences(user, %{ticket_notify_channel: "push"})
      push_ticket()

      run(TicketNewNotifier)
      assert_email_sent(fn email -> assert email.subject =~ "neue Anfrage" end)
    end

    test "a mail user's devices stay silent", %{user: user} do
      device(user, "one")
      push_ticket()

      run(TicketNewNotifier)
      refute_received {:push, _, _}
      assert_email_sent(fn email -> assert email.subject =~ "neue Anfrage" end)
    end
  end

  describe "assignment" do
    test "reassigning the current assignee tells nobody again", %{scope: scope} do
      colleague = user_fixture()
      granted_scope(colleague, ["info"])

      {:ok, ticket} = Tickets.assign(scope, ticket_fixture(), colleague.id)
      {:ok, _} = Tickets.assign(scope, ticket, colleague.id)

      assert [_only_one] = all_enqueued(worker: TicketAssignedNotifier)
    end

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
      ticket_fixture() |> age(inserted_at: ago(25, :hour), notified_at: ago(24, :hour))
      {:ok, _} = Tickets.take(scope, ticket_fixture() |> age(inserted_at: ago(25, :hour)))

      run(TicketNewNotifier)

      assert_email_sent(fn email ->
        refute_personal_data(email)
        assert email.to == [{"", user.email}]
        assert email.subject == "Postfach: eine Anfrage wartet"
        assert email.text_body =~ "niemandem zugewiesen"
      end)

      run(TicketNewNotifier)
      assert_no_email_sent()
    end

    test "not before the configured hour" do
      {:ok, _} = Settings.update_tickets(%{ticket_reminder_hour: 23})
      ticket_fixture() |> age(inserted_at: ago(25, :hour), notified_at: ago(24, :hour))

      if Bbh.Time.real_now().hour < 23 do
        run(TicketNewNotifier)
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
