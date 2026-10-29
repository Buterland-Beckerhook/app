defmodule Bbh.Tickets.QueueTest do
  # Not async: one test sets the global address prefix.
  use Bbh.DataCase, async: false

  import Bbh.AccountsFixtures
  import Bbh.TicketsFixtures

  alias Bbh.Tickets.Queue

  test "the seeded queues and their addresses" do
    assert Queue.keys() ==
             ~w(info vorstand offiziere jungschuetzen kinderfest webmaster mitgliedschaft)

    assert Queue.inbound_address("kinderfest") == "kinderfestausschuss@buterland-beckerhook.de"
    assert Queue.inbound_address("mitgliedschaft") == nil
    assert Queue.reply_address("mitgliedschaft") == "vorstand@buterland-beckerhook.de"
    assert Queue.reply_address("vorstand") == "vorstand@buterland-beckerhook.de"
    assert Queue.signature("info") == nil
    assert Queue.signature("mitgliedschaft") == "Vorstand"
    assert Queue.for_address(" Webmaster@Buterland-Beckerhook.de") == "webmaster"
    assert Queue.for_address("tickets@buterland-beckerhook.de") == nil
  end

  test "TICKET_ADDRESS_PREFIX turns every address into its test alias" do
    Application.put_env(:bbh, :ticket_address_prefix, "beta.")
    on_exit(fn -> Application.delete_env(:bbh, :ticket_address_prefix) end)

    assert Queue.inbound_address("info") == "beta.info@buterland-beckerhook.de"
    assert Queue.reply_address("mitgliedschaft") == "beta.vorstand@buterland-beckerhook.de"
    assert Queue.for_address("beta.vorstand@buterland-beckerhook.de") == "vorstand"
    # The real address is no longer a queue address on Beta.
    assert Queue.for_address("vorstand@buterland-beckerhook.de") == nil
  end

  test "the contact form offers neither webmaster nor mitgliedschaft" do
    keys = Enum.map(Queue.contact_options(), &elem(&1, 1))
    assert "info" in keys
    refute "webmaster" in keys
    refute "mitgliedschaft" in keys
    assert Queue.default() == "info"
  end

  test "create, update and deactivate a queue" do
    assert {:ok, queue} =
             Queue.create(%{
               "key" => "social",
               "label" => "Social Media",
               "inbound_address" => " Insta@Buterland-Beckerhook.de ",
               "signature" => "Social Media",
               "in_contact_form" => "true",
               "position" => "7"
             })

    assert queue.inbound_address == "insta@buterland-beckerhook.de"
    assert Queue.for_address("insta@buterland-beckerhook.de") == "social"
    assert {"Social Media", "social"} in Queue.contact_options()

    assert {:ok, _} = Queue.update(queue, %{"active" => "false"})
    refute {"Social Media", "social"} in Queue.contact_options()
    refute {"Social Media", "social"} in Queue.options()
    # Still a valid queue for its tickets.
    assert Queue.valid?("social")
  end

  test "keys and addresses are checked" do
    assert {:error, changeset} = Queue.create(%{"key" => "Social Media!", "label" => "x"})
    assert changeset.errors[:key]

    assert {:error, changeset} = Queue.create(%{"key" => "vorstand", "label" => "x"})
    assert changeset.errors[:key]

    assert {:error, changeset} =
             Queue.create(%{
               "key" => "zweit",
               "label" => "x",
               "inbound_address" => "VORSTAND@buterland-beckerhook.de"
             })

    assert changeset.errors[:inbound_address]

    assert {:error, changeset} =
             Queue.create(%{
               "key" => "kaputt",
               "label" => "x",
               "inbound_address" => "keine adresse"
             })

    assert changeset.errors[:inbound_address]
  end

  test "the fixed queues stay: info keeps an address, neither can be deactivated or deleted" do
    info = Queue.get("info")
    assert {:error, changeset} = Queue.update(info, %{"inbound_address" => ""})
    assert changeset.errors[:inbound_address]
    assert {:error, _} = Queue.update(info, %{"active" => "false"})
    assert {:error, _} = Queue.update(Queue.get("mitgliedschaft"), %{"active" => "false"})
    assert Queue.delete(info) == {:error, :protected}
    assert Queue.delete(Queue.get("mitgliedschaft")) == {:error, :protected}
  end

  test "a queue in use cannot be deleted" do
    {:ok, queue} = Queue.create(%{"key" => "social", "label" => "Social"})
    granted_scope(user_fixture(), ["social"])
    assert Queue.delete(queue) == {:error, :has_grants}

    {:ok, other} = Queue.create(%{"key" => "presse", "label" => "Presse"})
    ticket_fixture(queue: "presse")
    assert Queue.delete(other) == {:error, :has_tickets}

    {:ok, unused} = Queue.create(%{"key" => "leer", "label" => "Leer"})
    assert {:ok, _} = Queue.delete(unused)
    refute Queue.valid?("leer")
  end
end
