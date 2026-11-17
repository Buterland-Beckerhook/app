defmodule BbhWeb.Workers.UserDeleter do
  @moduledoc """
  Nightly: deletes the accounts whose „Löschen am" date (`users.delete_on`) has come
  (`Bbh.Accounts.delete_due_users/1`) and drops their live sessions.

  Self-healing like the other cron workers — it deletes everything due up to today, so
  a missed night is caught up by the next run.

  It lives in the web layer, unlike the other workers, because dropping the sessions is
  `BbhWeb.UserAuth`'s job; that keeps the domain free of calls into `BbhWeb`.
  """
  use Oban.Worker, queue: :default, max_attempts: 3

  alias BbhWeb.UserAuth

  require Logger

  @impl Oban.Worker
  def perform(_job) do
    for {user, tokens} <- Bbh.Accounts.delete_due_users(Bbh.Accounts.local_today()) do
      UserAuth.disconnect_sessions(tokens)
      Logger.info("Deleted user #{user.email} (scheduled for #{user.delete_on})")
    end

    :ok
  end
end
