defmodule Bbh.ReleaseRekeyTest do
  # Not async: swaps the Vault key configuration.
  use Bbh.DataCase, async: false

  import Bbh.TicketsFixtures

  alias Bbh.Vault

  test "rekey_tickets moves every value to the current key and stays readable" do
    previous = Application.get_env(:bbh, Vault)
    Application.put_env(:bbh, Vault, Keyword.put(previous, :current_key, "1"))
    on_exit(fn -> Application.put_env(:bbh, Vault, previous) end)

    ticket = ticket_fixture(payload: %{"x" => 1})
    assert <<1, 1, _::binary>> = Repo.get!(Bbh.Tickets.Ticket, ticket.id).subject_enc

    Application.put_env(:bbh, Vault, previous)
    ExUnit.CaptureIO.capture_io(fn -> Bbh.Release.rekey_tickets() end)

    raw = Repo.get!(Bbh.Tickets.Ticket, ticket.id)
    assert <<1, 2, _::binary>> = raw.subject_enc
    assert <<1, 2, _::binary>> = raw.payload_enc

    admin = Bbh.Accounts.Scope.for_user(Bbh.AccountsFixtures.admin_user_fixture())
    {:ok, loaded} = Bbh.Tickets.get_ticket(admin, ticket.number)
    assert loaded.subject == "Frage zum Schützenfest"
    assert loaded.payload == %{"x" => 1}
    assert [%{body: "Wann ist das nächste Schützenfest?"}] = loaded.messages

    # Rerunning finds nothing left to do.
    assert %{"tickets" => 0, "ticket_messages" => 0} =
             ExUnit.CaptureIO.with_io(fn -> Bbh.Release.rekey_tickets() end) |> elem(0)
  end
end
