defmodule BbhWeb.MembershipController do
  use BbhWeb, :controller

  require Logger

  alias Bbh.Content

  # Salt for the signed form-issue timestamp (see check_timing/2).
  @form_token_salt "membership_form"
  # A genuine visitor takes at least this long to fill in the form; anything
  # faster is a bot submitting the parsed fields programmatically.
  @min_fill_seconds 3
  # Upper bound on how long an issued form stays submittable.
  @max_form_age_seconds 7_200

  # Slugs of the (hidden, published) content pages whose blocks are rendered above
  # and below the form. Editable through the normal page editor (/admin/seiten).
  @intro_slug "mitglied-werden-intro"
  @download_slug "mitglied-werden-pdf"

  def new(conn, _params) do
    render_form(conn, %{}, %{})
  end

  def create(conn, params) do
    # Validate first so a human with empty/invalid fields sees the real field
    # errors instead of a generic spam message; only fully valid submissions
    # are then subjected to the (silent) spam checks.
    case Bbh.Membership.validate(params) do
      {:error, errors} ->
        render_form(conn, params, errors)

      {:ok, data} ->
        case check_spam(conn, params) do
          :ok ->
            if Bbh.Tickets.enabled?(),
              do: create_ticket(conn, data, params),
              else: deliver(conn, data, params)

          :rate_limited ->
            Logger.warning("Membership form rejected: rate limit")

            conn
            |> put_flash(:error, "Zu viele Anfragen. Bitte später erneut versuchen.")
            |> render_form(params, %{})

          {:spam, reason} ->
            Logger.warning("Membership form rejected as spam (#{reason})")

            conn
            |> put_flash(:error, "Spam-Schutz fehlgeschlagen. Bitte versuchen Sie es erneut.")
            |> render_form(params, %{})
        end
    end
  end

  # Postfach: the application becomes a ticket (with the submission record standing in
  # for date and signature); the applicant still gets their copy of the SEPA mandate.
  defp create_ticket(conn, data, params) do
    record = %{
      submitted_at: DateTime.utc_now(:second),
      client_ip: BbhWeb.ClientIp.get(conn),
      altcha_verified: Bbh.Altcha.enabled?()
    }

    case Bbh.Tickets.create_from_membership(data, record) do
      {:ok, _ticket} ->
        # The application is in; a failed copy is logged, not shown as a failure.
        Bbh.Membership.deliver_applicant_copy(data)

        conn
        |> put_flash(
          :info,
          "Vielen Dank! Ihr Aufnahmeantrag ist bei uns eingegangen. Eine Kopie geht an Ihre E-Mail-Adresse."
        )
        |> redirect(to: ~p"/verein/mitglied-werden")

      {:error, reason} ->
        Logger.error("Membership form ticket failed: #{inspect(reason)}")

        conn
        |> put_flash(
          :error,
          "Ihr Antrag konnte nicht gesendet werden. Bitte versuchen Sie es später erneut."
        )
        |> render_form(params, %{})
    end
  end

  defp deliver(conn, data, params) do
    case Bbh.Membership.deliver(data) do
      {:ok, _} ->
        conn
        |> put_flash(
          :info,
          "Vielen Dank! Ihr Aufnahmeantrag wurde gesendet. Eine Kopie geht an Ihre E-Mail-Adresse."
        )
        |> redirect(to: ~p"/verein/mitglied-werden")

      {:error, reason} ->
        Logger.error("Membership form delivery failed: #{inspect(reason)}")

        conn
        |> put_flash(
          :error,
          "Ihr Antrag konnte nicht gesendet werden. Bitte versuchen Sie es später erneut."
        )
        |> render_form(params, %{})
    end
  end

  # Honeypot, then submit-timing, then the Altcha proof of work. Each layer is
  # independent so any one tripping is enough to reject.
  defp check_spam(conn, params) do
    cond do
      Bbh.Membership.honeypot_filled?(params) -> {:spam, "honeypot"}
      not timing_ok?(conn, params) -> {:spam, "timing"}
      Bbh.Altcha.enabled?() and not Bbh.Altcha.verify(params["altcha"]) -> {:spam, "altcha"}
      rate_limited?(conn) -> :rate_limited
      true -> :ok
    end
  end

  # Last, so only submissions that passed every spam check count: each one sends mail
  # or opens a ticket, and the proof of work alone is cheap for a script. A family may apply together from one address.
  defp rate_limited?(conn) do
    BbhWeb.RateLimit.check(
      "membership_submit",
      BbhWeb.RateLimit.client_ip(conn),
      10,
      :timer.hours(1)
    ) !=
      :ok
  end

  defp timing_ok?(conn, params) do
    case Phoenix.Token.verify(conn, @form_token_salt, params["form_ts"],
           max_age: @max_form_age_seconds
         ) do
      {:ok, issued_at} -> System.os_time(:second) - issued_at >= @min_fill_seconds
      {:error, _} -> false
    end
  end

  defp render_form(conn, params, errors) do
    render(conn, :new,
      page_title: "Mitglied werden",
      params: params,
      errors: errors,
      intro_blocks: blocks_for(@intro_slug),
      download_blocks: blocks_for(@download_slug),
      min_age: Bbh.Membership.min_age(),
      max_child_age: Bbh.Membership.max_child_age(),
      form_token: Phoenix.Token.sign(conn, @form_token_salt, System.os_time(:second)),
      altcha: Bbh.Altcha.enabled?() && Bbh.Altcha.challenge()
    )
  end

  # Resolved content blocks of a published page, or [] if the page does not exist yet.
  defp blocks_for(slug) do
    case Content.get_published_page(slug) do
      {_page, blocks} -> blocks
      nil -> []
    end
  end
end
