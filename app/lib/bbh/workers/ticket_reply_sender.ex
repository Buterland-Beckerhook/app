defmodule Bbh.Workers.TicketReplySender do
  @moduledoc """
  Sends one reply from the Postfach through `Bbh.TicketMailer`. The job names the
  message by id only — Oban args live in the database and its dumps.

  Retries on a delivery error; when the last attempt fails, a system message on the
  ticket says so, and the thread shows the reply as not sent. Logged redacted: the
  recipient and subject are the requester's.
  """
  use Oban.Worker,
    queue: :notifications,
    max_attempts: 5,
    unique: [period: :infinity, keys: [:message_id]]

  alias Bbh.Tickets

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"message_id" => message_id}, attempt: attempt, max_attempts: max}) do
    case Tickets.deliver_reply(message_id) do
      :ok ->
        :ok

      {:error, reason} ->
        if attempt >= max, do: Tickets.reply_failed(message_id)
        {:error, reason}
    end
  end
end
