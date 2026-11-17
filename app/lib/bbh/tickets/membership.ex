defmodule Bbh.Tickets.Membership do
  @moduledoc """
  What only a membership application (`kind: "membership"`) has: the Mitgliedsnummer and
  the application as PDF.
  """
  import Bbh.Tickets.Store, only: [authorize: 2, authorize_view: 2, update_and_log: 4]

  alias Bbh.Accounts.Scope
  alias Bbh.Tickets
  alias Bbh.Tickets.Ticket
  alias Bbh.Vault

  @doc """
  Sets the Mitgliedsnummer on a membership ticket (stored encrypted in the payload; it
  is also the SEPA mandate reference).
  """
  def set_member_number(%Scope{} = scope, %Ticket{kind: "membership"} = ticket, number) do
    with :ok <- authorize(scope, ticket) do
      payload = Map.put(ticket.payload || %{}, "member_number", String.trim(number || ""))

      ticket
      |> Ecto.Changeset.change(payload: payload)
      |> Vault.encrypt_changes("tickets", Ticket.encrypted_fields())
      |> update_and_log(scope, "member_number_set", %{})
    end
  end

  def set_member_number(_scope, _ticket, _number), do: {:error, :not_membership}

  @doc """
  The membership application of a ticket as PDF (`Bbh.Tickets.Pdf`), logged as
  `pdf_exported`. The PDF is returned, never stored.
  """
  def export_pdf(%Scope{user: user} = scope, %Ticket{kind: "membership"} = ticket) do
    with :ok <- authorize_view(scope, ticket),
         {:ok, pdf} <- Bbh.Tickets.Pdf.membership_application(ticket, user) do
      Tickets.log_event(ticket, user, "pdf_exported", %{})
      {:ok, pdf}
    end
  end

  def export_pdf(_scope, _ticket), do: {:error, :not_membership}
end
