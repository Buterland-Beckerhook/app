defmodule Bbh.Tickets.Retention do
  @moduledoc """
  How long the Postfach keeps what (plan §10) — stated in the Datenschutzerklärung,
  hence env, not a setting in the admin (`deploy/.env.example`):

    * closed tickets are soft-deleted `TICKET_RETENTION_MONTHS` (12) after closing;
    * soft-deleted tickets are purged — messages and attachments with them —
      `TICKET_PURGE_DAYS` (30) after deletion, so an accidental delete can be undone
      in between;
    * spam is purged `TICKET_PURGE_DAYS` after its last activity, restorable until then
      from the "Spam" tab;
    * the history (`ticket_events`) goes after `TICKET_EVENT_RETENTION_MONTHS` (12); a
      purged ticket's events keep only its number.

  Before a ticket is purged its mail goes from the IMAP server; if that fails, the
  ticket waits for the next run. Run nightly by `Bbh.Workers.TicketPruner`.
  """
  import Ecto.Query

  require Logger

  alias Bbh.Repo
  alias Bbh.Tickets.{Event, Ticket}
  alias Bbh.Workers.ImapCleanup

  @doc "Runs all steps; returns the counts."
  def run(now \\ DateTime.utc_now(:second)) do
    soft_deleted = soft_delete_closed(now)
    purged = purge(now)
    events = prune_events(now)
    %{soft_deleted: soft_deleted, purged: purged, events: events}
  end

  @doc "Soft-deletes tickets closed longer than the retention period."
  def soft_delete_closed(now) do
    cutoff = DateTime.add(now, -retention_months() * 30, :day)

    tickets =
      Repo.all(
        from t in Ticket,
          where: t.status == "closed" and is_nil(t.deleted_at) and t.closed_at < ^cutoff
      )

    for ticket <- tickets do
      ticket |> Ecto.Changeset.change(deleted_at: now) |> Repo.update!()
      Bbh.Tickets.log_event(ticket, nil, "deleted", %{reason: "retention"})
    end

    length(tickets)
  end

  @doc "Hard-deletes soft-deleted tickets and old spam, after their server copies."
  def purge(now) do
    cutoff = DateTime.add(now, -purge_days(), :day)

    Repo.all(
      from t in Ticket,
        where:
          (not is_nil(t.deleted_at) and t.deleted_at < ^cutoff) or
            (t.status == "spam" and is_nil(t.deleted_at) and t.last_activity_at < ^cutoff)
    )
    |> Enum.count(&purge_ticket/1)
  end

  defp purge_ticket(ticket) do
    case ImapCleanup.clean_ticket(ticket, "delete") do
      :ok ->
        delete!(ticket)

      {:error, :imap_disabled} ->
        # Copies recorded, but no mailbox to reach: the database is what we control.
        Logger.warning("Postfach purge: ticket #{ticket.number} has server copies, IMAP is off")
        delete!(ticket)

      {:error, reason} ->
        Logger.warning(
          "Postfach purge: ticket #{ticket.number} kept, server copy: #{inspect(reason)}"
        )

        false
    end
  end

  # Messages and attachments go by cascade; events keep the number (ticket_id nilified).
  defp delete!(ticket) do
    Repo.transact(fn ->
      Repo.update_all(from(e in Event, where: e.ticket_id == ^ticket.id),
        set: [ticket_number: ticket.number]
      )

      Repo.delete!(ticket)
      Repo.insert!(%Event{action: "purged", ticket_number: ticket.number, meta: %{}})
      {:ok, true}
    end)
    |> elem(1)
  end

  @doc "Deletes history entries older than the event retention."
  def prune_events(now) do
    cutoff = DateTime.add(now, -event_retention_months() * 30, :day)
    {count, _} = Repo.delete_all(from e in Event, where: e.inserted_at < ^cutoff)
    count
  end

  def retention_months, do: Application.get_env(:bbh, :ticket_retention_months, 12)
  def purge_days, do: Application.get_env(:bbh, :ticket_purge_days, 30)
  def event_retention_months, do: Application.get_env(:bbh, :ticket_event_retention_months, 12)
end
