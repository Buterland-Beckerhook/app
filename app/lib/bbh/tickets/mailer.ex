defmodule Bbh.Tickets.Mailer do
  @moduledoc """
  The Postfach's own mailer: replies to requesters go out through the `tickets@`
  mailbox (`TICKET_SMTP_USERNAME` / `TICKET_SMTP_PASSWORD`, same relay as `Bbh.Mailer`),
  sending as the queue addresses that are its aliases.

  Kept apart from `Bbh.Mailer` (`noreply@`, system mail) so the two credentials never
  mix: bounces of replies land in the ticket inbox, those of login mails don't, and a
  leaked `noreply@` password cannot send as `vorstand@`. Deliver through
  `Bbh.Mailer.deliver_logged/3` with `mailer: Bbh.Tickets.Mailer`.
  """
  use Swoosh.Mailer, otp_app: :bbh

  @doc "Whether replies can be sent (the mailbox is configured)."
  def enabled?, do: Application.get_env(:bbh, __MODULE__, [])[:adapter] != nil
end
