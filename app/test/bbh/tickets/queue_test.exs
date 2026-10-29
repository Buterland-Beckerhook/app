defmodule Bbh.Tickets.QueueTest do
  use ExUnit.Case, async: false

  alias Bbh.Tickets.Queue

  test "addresses default to the club domain" do
    assert Queue.inbound_address("kinderfest") == "kinderfestausschuss@buterland-beckerhook.de"
    assert Queue.inbound_address("mitgliedschaft") == nil
    assert Queue.reply_address("mitgliedschaft") == "vorstand@buterland-beckerhook.de"
    assert Queue.for_address(" Webmaster@Buterland-Beckerhook.de") == "webmaster"
    assert Queue.for_address("tickets@buterland-beckerhook.de") == nil
  end

  test "TICKET_QUEUE_ADDRESSES overrides single queues" do
    Application.put_env(:bbh, :ticket_queue_addresses, "info=info-beta@example.test")
    on_exit(fn -> Application.delete_env(:bbh, :ticket_queue_addresses) end)

    assert Queue.inbound_address("info") == "info-beta@example.test"
    assert Queue.for_address("info-beta@example.test") == "info"
    assert Queue.inbound_address("vorstand") == "vorstand@buterland-beckerhook.de"
  end

  test "the contact form offers neither webmaster nor mitgliedschaft" do
    keys = Enum.map(Queue.contact_options(), &elem(&1, 1))
    assert "info" in keys
    refute "webmaster" in keys
    refute "mitgliedschaft" in keys
    assert Queue.default() == "info"
  end
end
