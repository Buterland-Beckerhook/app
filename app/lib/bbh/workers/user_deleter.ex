defmodule Bbh.Workers.UserDeleter do
  @moduledoc """
  Nightly: deletes the accounts whose „Löschen am" date (`users.delete_on`) has come
  (`Bbh.Accounts.delete_due_users/1`) and drops their live sessions.

  Self-healing like the other cron workers — it deletes everything due up to today, so
  a missed night is caught up by the next run.
  """
  use Oban.Worker, queue: :default, max_attempts: 3

  require Logger

  @impl Oban.Worker
  def perform(_job) do
    for {user, tokens} <- Bbh.Accounts.delete_due_users(Bbh.Accounts.local_today()) do
      BbhWeb.UserAuth.disconnect_sessions(tokens)
      Logger.info("Deleted user #{user.email} (scheduled for #{user.delete_on})")
    end

    :ok
  end
end
