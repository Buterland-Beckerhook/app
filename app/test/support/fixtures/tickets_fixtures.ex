defmodule Bbh.TicketsFixtures do
  @moduledoc "Test helpers for the Postfach."

  alias Bbh.Accounts.Scope
  alias Bbh.Tickets

  def ticket_fixture(attrs \\ %{}) do
    attrs = Map.new(attrs)
    {body, attrs} = Map.pop(attrs, :body, "Wann ist das nächste Schützenfest?")

    {:ok, ticket} =
      Tickets.create_ticket(
        Enum.into(attrs, %{
          queue: "info",
          kind: "contact",
          subject: "Frage zum Schützenfest",
          requester_name: "Erika Musterfrau",
          requester_email: "erika@example.com"
        }),
        %{body: body, from: "erika@example.com"}
      )

    ticket
  end

  @doc "A scope for `user` with the given queue grants (stored, so the scope is real)."
  def granted_scope(user, queues) do
    admin = Bbh.AccountsFixtures.admin_user_fixture()
    {:ok, _} = Bbh.Tickets.Grants.set_grants(admin, user, queues)
    Scope.for_user(user)
  end
end
