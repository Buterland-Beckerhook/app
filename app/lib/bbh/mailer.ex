defmodule Bbh.Mailer do
  use Swoosh.Mailer, otp_app: :bbh

  require Logger

  @doc """
  Deliver an email with structured logging around the send.

  Logs the attempt (subject, recipients, configured relay), then the outcome —
  `delivered` with the adapter metadata, or `FAILED` with the relay and the exact
  error reason. Delivery that *raises* or *exits* (some SMTP failures exit the
  `:gen_smtp_client` process on connect/timeout) is caught and logged too, and
  turned into `{:error, {:exception, exception}}` / `{:error, {kind, reason}}` so
  callers keep the `{:ok, _} | {:error, _}` contract instead of crashing — which
  is exactly the connection/DNS failure this logging exists to diagnose.

  Credentials are never logged — only the relay host.
  """
  def deliver_logged(email, context \\ "mail") do
    relay = Application.get_env(:bbh, __MODULE__, [])[:relay]

    Logger.info(
      "[mail:#{context}] sending subject=#{inspect(email.subject)} " <>
        "to=#{inspect(email.to)} relay=#{inspect(relay)}"
    )

    try do
      case deliver(email) do
        {:ok, meta} = ok ->
          Logger.info("[mail:#{context}] delivered to=#{inspect(email.to)} meta=#{inspect(meta)}")
          ok

        {:error, reason} = err ->
          Logger.error(
            "[mail:#{context}] delivery FAILED to=#{inspect(email.to)} " <>
              "relay=#{inspect(relay)} reason=#{inspect(reason)}"
          )

          err
      end
    rescue
      exception ->
        Logger.error(
          "[mail:#{context}] delivery raised relay=#{inspect(relay)}: " <>
            Exception.format(:error, exception, __STACKTRACE__)
        )

        {:error, {:exception, exception}}
    catch
      kind, reason ->
        Logger.error(
          "[mail:#{context}] delivery crashed (#{kind}) relay=#{inspect(relay)}: " <>
            Exception.format(kind, reason, __STACKTRACE__)
        )

        {:error, {kind, reason}}
    end
  end
end
