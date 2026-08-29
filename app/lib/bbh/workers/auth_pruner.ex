defmodule Bbh.Workers.AuthPruner do
  @moduledoc """
  Nightly sweep of dead authentication artifacts: expired or long-revoked API tokens, and
  spent or expired OAuth authorization codes.

  Nightly rather than hourly because neither kind still works by the time it is swept —
  `Bbh.ApiTokens.verify/2` and `Bbh.OAuth.exchange_code/1` both refuse them on their own.
  This only reclaims rows.

  Tokens keep a month of grace after revocation so `last_used_at` stays readable, which is
  exactly what someone wants after a leak. Codes get no such grace: they are worthless a
  minute after issue and carry nothing worth reading.

  Self-healing like the other cron workers — a plain delete over a window, so a missed run
  is fully repaired by the next one.
  """
  use Oban.Worker, queue: :default, max_attempts: 3

  require Logger

  @impl Oban.Worker
  def perform(_job) do
    tokens = Bbh.ApiTokens.prune()
    codes = Bbh.OAuth.prune_codes()

    if tokens > 0 or codes > 0 do
      Logger.info("Pruned #{tokens} dead API token(s) and #{codes} OAuth code(s)")
    end

    :ok
  end
end
