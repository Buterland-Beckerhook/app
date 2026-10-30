defmodule Bbh.Tickets.Mailbox do
  @moduledoc """
  The Postfach's collector mailbox on the mail server (`tickets@`, mailcow): connection
  settings from `TICKET_IMAP_*` and the folders the import files mail into.

  Without `TICKET_IMAP_HOST` the import is off — Beta must get its own test mailbox,
  never Prod's: a poller with Prod credentials would take and delete real mail.
  """

  @inbox "INBOX"
  @imported "Tickets/Importiert"
  @ignored "Tickets/Ignoriert"
  @junk "Junk"

  def inbox, do: @inbox
  @doc "Imported mail, kept until work on its ticket starts."
  def imported, do: @imported
  @doc "Auto-replies, bounces, loops, oversized and unreadable mail — for a human glance."
  def ignored, do: @ignored
  @doc "Spam; mailcow's rspamd learns from mail moved here."
  def junk, do: @junk

  @doc """
  Whether the poller also reads `Junk` (`TICKET_IMPORT_JUNK`, off by default): mail
  rspamd filtered at delivery then shows up as spam tickets, so a false positive can be
  rescued. Off, it never reaches the Postfach.
  """
  def import_junk?, do: Application.get_env(:bbh, :ticket_import_junk, false) == true

  @doc "Whether the import is configured."
  def enabled?, do: config()[:host] not in [nil, ""]

  @doc "Connects and logs in, or `:disabled`."
  def connect do
    if enabled?() do
      c = config()

      Bbh.Tickets.Imap.connect(
        host: c[:host],
        port: c[:port],
        tls: Keyword.get(c, :tls, true),
        username: c[:username],
        password: c[:password],
        max_literal: max_mail_bytes()
      )
    else
      :disabled
    end
  end

  @doc "Largest mail the import takes (`TICKET_MAX_MAIL_MB`)."
  def max_mail_bytes, do: Application.get_env(:bbh, :ticket_max_mail_mb, 25) * 1_048_576

  defp config, do: Application.get_env(:bbh, :ticket_imap, [])
end
