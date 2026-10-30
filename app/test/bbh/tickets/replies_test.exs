defmodule Bbh.Tickets.RepliesTest do
  # Not async: one test swaps the Tickets.Mailer adapter.
  use Bbh.DataCase, async: false
  use Oban.Testing, repo: Bbh.Repo

  import Bbh.AccountsFixtures
  import Bbh.TicketsFixtures

  alias Bbh.Tickets
  alias Bbh.Tickets.{Message, ReplyMail, Threading, Ticket}
  alias Bbh.Workers.TicketReplySender

  defmodule FailingAdapter do
    def deliver(_email, _config), do: {:error, :rejected}
    def deliver_many(_emails, _config), do: {:error, :rejected}
    def validate_config(_config), do: :ok
  end

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

  defp loaded(scope, ticket) do
    {:ok, ticket} = Tickets.get_ticket(scope, ticket.number)
    ticket
  end

  setup do
    user = user_fixture()
    scope = granted_scope(user, ["info", "mitgliedschaft"])
    flush_emails()
    %{user: user, scope: scope}
  end

  describe "reply/4" do
    test "stores the reply, takes the ticket, sets the status and queues the mail", %{
      scope: scope,
      user: user
    } do
      ticket = loaded(scope, ticket_fixture())

      assert {:ok, updated} = Tickets.reply(scope, ticket, "  Am 12. Juli.  ")
      assert updated.status == "waiting"
      assert updated.assignee_id == user.id

      [_, out] = loaded(scope, ticket).messages

      assert %{direction: "out", body: "Am 12. Juli.", to: "erika@example.com", sent_at: nil} =
               out

      assert out.from == "info@buterland-beckerhook.de"
      assert out.message_id =~ ~r/^<[0-9a-f-]+@buterland-beckerhook\.de>$/

      assert_enqueued(worker: TicketReplySender, args: %{message_id: out.id})
      [job] = all_enqueued(worker: TicketReplySender)
      refute inspect(job.args) =~ "erika"
    end

    test "can close right away; refuses an empty reply and spam", %{scope: scope} do
      ticket = loaded(scope, ticket_fixture())

      assert {:ok, %{status: "closed", closed_at: %DateTime{}}} =
               Tickets.reply(scope, ticket, "Erledigt.", "closed")

      assert Tickets.reply(scope, ticket, "  ") == {:error, :empty}

      {:ok, spam} = Tickets.mark_spam(scope, ticket_fixture())
      assert Tickets.reply(scope, loaded(scope, spam), "x") == {:error, :spam}
    end

    test "is refused while the reply mailbox is not configured", %{scope: scope} do
      previous = Application.get_env(:bbh, Bbh.Tickets.Mailer)
      Application.put_env(:bbh, Bbh.Tickets.Mailer, adapter: nil)
      on_exit(fn -> Application.put_env(:bbh, Bbh.Tickets.Mailer, previous) end)

      assert Tickets.reply(scope, loaded(scope, ticket_fixture()), "x") ==
               {:error, :replies_disabled}
    end
  end

  describe "sending" do
    test "goes out as the queue, threaded and with the request quoted", %{scope: scope} do
      ticket = loaded(scope, ticket_fixture(body: "Wann ist das Fest?"))
      {:ok, _} = Tickets.reply(scope, ticket, "Am 12. Juli.")
      [job] = all_enqueued(worker: TicketReplySender)

      assert :ok = perform_job(TicketReplySender, job.args)
      [email] = sent_emails()

      # The general queue speaks for the club; no "Allgemein".
      assert email.from == {"Schützenverein Buterland-Beckerhook", "info@buterland-beckerhook.de"}
      refute email.text_body =~ "Allgemein"

      assert email.reply_to == email.from
      assert email.to == [{"Erika Musterfrau", "erika@example.com"}]
      assert email.subject == "Ihre Anfrage [##{Ticket.reference(ticket)}]"
      assert email.headers["Auto-Submitted"] == "no"
      assert email.headers["Message-ID"] =~ "@buterland-beckerhook.de>"
      assert email.text_body =~ "Am 12. Juli."
      assert email.text_body =~ "> Wann ist das Fest?"

      out = Repo.get_by!(Message, direction: "out")
      assert out.sent_at

      # A second run of the same job sends nothing.
      assert :ok = perform_job(TicketReplySender, job.args)
      assert sent_emails() == []
    end

    test "a membership reply comes from the Vorstand and never quotes the application", %{
      scope: scope
    } do
      ticket =
        loaded(
          scope,
          ticket_fixture(queue: "mitgliedschaft", kind: "membership", body: "IBAN DE89…")
        )

      {:ok, _} = Tickets.reply(scope, ticket, "Willkommen!")
      [job] = all_enqueued(worker: TicketReplySender)
      :ok = perform_job(TicketReplySender, job.args)
      [email] = sent_emails()

      # Sent as the Vorstand, so named as the Vorstand.
      assert email.from ==
               {"Schützenverein Buterland-Beckerhook – Vorstand",
                "vorstand@buterland-beckerhook.de"}

      assert email.text_body =~ "\nVorstand\n"
      assert email.subject =~ "Ihr Aufnahmeantrag"
      refute email.text_body =~ "IBAN"
    end

    test "answers an inbound mail with In-Reply-To and a Re: subject" do
      ticket = %Ticket{
        kind: "email",
        subject: "Frage",
        number: 7,
        inserted_at: ~U[2026-10-29 10:00:00Z],
        queue: "info",
        requester_name: "Max"
      }

      message = %{
        to: "max@example.com",
        body: "Antwort",
        message_id: "<a@buterland-beckerhook.de>"
      }

      inbound = %{
        header_message_id: "<orig@example.com>",
        body: "Frage?",
        inserted_at: ~U[2026-10-29 10:00:00Z]
      }

      email = ReplyMail.build(ticket, message, inbound)
      assert email.subject == "Re: Frage [#BB-2026-0007]"
      assert email.headers["In-Reply-To"] == "<orig@example.com>"
      assert email.headers["References"] == "<orig@example.com>"

      assert ReplyMail.subject(%{ticket | subject: "AW: Frage [#BB-2026-0007]"}) ==
               "AW: Frage [#BB-2026-0007]"

      assert ReplyMail.subject(%{ticket | subject: "AW: Frage"}) == "AW: Frage [#BB-2026-0007]"
    end

    test "a reply that cannot be sent is marked on the ticket after the last attempt", %{
      scope: scope
    } do
      previous = Application.get_env(:bbh, Bbh.Tickets.Mailer)
      Application.put_env(:bbh, Bbh.Tickets.Mailer, adapter: FailingAdapter)
      on_exit(fn -> Application.put_env(:bbh, Bbh.Tickets.Mailer, previous) end)

      ticket = loaded(scope, ticket_fixture())
      {:ok, _} = Tickets.reply(scope, ticket, "Hallo")
      [job] = all_enqueued(worker: TicketReplySender)

      assert {:error, :delivery_failed} = perform_job(TicketReplySender, job.args, attempt: 1)
      refute Repo.get_by(Message, direction: "system")

      assert {:error, :delivery_failed} = perform_job(TicketReplySender, job.args, attempt: 5)
      [system] = loaded(scope, ticket).messages |> Enum.filter(&(&1.direction == "system"))
      assert system.body =~ "konnte nicht gesendet werden"
    end
  end

  describe "threading" do
    setup %{scope: scope} do
      ticket = loaded(scope, ticket_fixture())
      {:ok, _} = Tickets.reply(scope, ticket, "Antwort")
      out = Repo.get_by!(Message, direction: "out")
      %{ticket: ticket, out: out}
    end

    test "by our Message-ID", %{ticket: ticket, out: out} do
      assert {:ok, %{id: id}} = Threading.match(%{message_ids: ["<other@x>", out.message_id]})
      assert id == ticket.id
    end

    test "by the subject token only from the requester once answered", %{ticket: ticket} do
      subject = "Re: Ihre Anfrage [##{Ticket.reference(ticket)}]"

      assert {:ok, _} = Threading.match(%{subject: subject, from: "ERIKA@example.com"})
      assert Threading.match(%{subject: subject, from: "fremd@example.com"}) == :none
    end

    test "by the token from anyone while never answered" do
      fresh = ticket_fixture()
      subject = "[##{Ticket.reference(fresh)}] Nachtrag"
      assert {:ok, %{id: id}} = Threading.match(%{subject: subject, from: "anders@example.com"})
      assert id == fresh.id
    end

    test "nothing for unknown numbers, deleted tickets or plain mail", %{ticket: ticket} do
      assert Threading.match(%{subject: "[#BB-2026-9999]", from: "erika@example.com"}) == :none
      assert Threading.match(%{subject: "Hallo", from: "erika@example.com"}) == :none

      admin = Bbh.Accounts.Scope.for_user(admin_user_fixture())
      {:ok, _} = Tickets.delete_ticket(admin, ticket)
      out = Repo.get_by!(Message, direction: "out")
      assert Threading.match(%{message_ids: [out.message_id]}) == :none
    end

    test "an answer reopens the ticket and tells the assignee", %{ticket: ticket, user: user} do
      waiting = Repo.get!(Ticket, ticket.id)
      assert waiting.status == "waiting"
      flush_emails()

      assert {:ok, {reopened, message}} =
               Tickets.add_inbound(waiting, %{body: "Danke!", from: "erika@example.com"})

      assert reopened.status == "open"
      assert message.direction == "in"
      assert [email] = sent_emails()
      assert email.to == [{"", user.email}]
      assert email.subject =~ "neue Antwort"
      refute email.text_body =~ "Danke"
    end
  end
end
