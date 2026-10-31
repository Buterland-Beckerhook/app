defmodule Bbh.Tickets.ServerCopies do
  @moduledoc """
  The copies of imported mails on the IMAP server. The importer records where it filed
  each one (`Bbh.Workers.ImapPoller`); once a ticket is worked, marked as spam, taken
  back from spam or deleted, a `Bbh.Workers.ImapCleanup` job deletes or moves the copy
  and reports back here. Holds no personal data: messages are addressed by id and the
  hashed Message-ID.
  """
  import Ecto.Query
  alias Bbh.Repo
  alias Bbh.Tickets
  alias Bbh.Tickets.{Message, Ticket}

  @doc """
  Where the import filed an inbound mail on the server, so the copy can be deleted or
  moved later. Returns the message's ticket, or nil.
  """
  def record(message_id_hash, mailbox, uidvalidity, uid) do
    query =
      from m in Message,
        where:
          m.direction == "in" and m.message_id == ^message_id_hash and
            is_nil(m.server_copy_removed_at)

    case Repo.one(query) do
      nil ->
        nil

      message ->
        message
        |> Ecto.Changeset.change(
          imap_mailbox: mailbox,
          imap_uidvalidity: uidvalidity,
          imap_uid: uid
        )
        |> Repo.update!()

        Repo.get(Ticket, message.ticket_id)
    end
  end

  @doc "The inbound messages of a ticket that still have a copy on the server."
  def list(%Ticket{id: id}), do: Repo.all(with_copy(id))

  @doc "The cleanup moved a copy (to Junk or back): remember where it is now."
  def moved(%Message{} = message, folder, uidvalidity, uid, action) do
    message
    |> Ecto.Changeset.change(imap_mailbox: folder, imap_uidvalidity: uidvalidity, imap_uid: uid)
    |> Repo.update!()

    with %Ticket{} = ticket <- Repo.get(Ticket, message.ticket_id) do
      Tickets.log_event(ticket, nil, "server_copy_moved", %{action: action})
    end

    :ok
  end

  @doc "The cleanup deleted a copy (or found it gone)."
  def removed(%Message{} = message, action) do
    message
    |> Ecto.Changeset.change(server_copy_removed_at: DateTime.utc_now(:second))
    |> Repo.update!()

    with %Ticket{} = ticket <- Repo.get(Ticket, message.ticket_id) do
      Tickets.log_event(ticket, nil, "server_copy_removed", %{action: action})
    end

    :ok
  end

  @doc """
  After a status change from `old` to `new`: the copy goes once work starts (plan
  §6.2), on the first change away from `new`; marked as spam, it moves to Junk
  instead, so rspamd learns. Form tickets have no server copy; the job is only queued
  when there is one.
  """
  def release_on_change(%Ticket{status: old}, %Ticket{status: new} = ticket) do
    action =
      cond do
        new == "spam" and old != "spam" -> "junk"
        old == "new" and new != "new" -> "delete"
        true -> nil
      end

    if action, do: cleanup(ticket, action)
    :ok
  end

  @doc "Taken back from spam: its mail leaves Junk again (rspamd learns \"not spam\")."
  def release_from_junk(ticket), do: cleanup(ticket, "unjunk")

  @doc "A deleted ticket's mail has no reason to stay on the server."
  def release_deleted(ticket), do: cleanup(ticket, "delete")

  @doc """
  After an inbound mail of a ticket that is already in work was filed on the server:
  its copy can go right away.
  """
  def release_new(%Ticket{status: status} = ticket) when status not in ["new", "spam"],
    do: release_on_change(%{ticket | status: "new"}, ticket)

  def release_new(_ticket), do: :ok

  defp cleanup(%Ticket{id: id} = ticket, action) do
    if Repo.exists?(with_copy(id)) do
      %{ticket_id: ticket.id, action: action} |> Bbh.Workers.ImapCleanup.new() |> Oban.insert!()
    end
  end

  defp with_copy(ticket_id) do
    from m in Message,
      where:
        m.ticket_id == ^ticket_id and m.direction == "in" and not is_nil(m.imap_uid) and
          is_nil(m.server_copy_removed_at)
  end
end
