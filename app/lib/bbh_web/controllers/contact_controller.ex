defmodule BbhWeb.ContactController do
  use BbhWeb, :controller

  require Logger

  # Salt for the signed form-issue timestamp (see check_timing/2).
  @form_token_salt "contact_form"
  # A genuine visitor takes at least this long to fill in the form; anything
  # faster is a bot submitting the parsed fields programmatically.
  @min_fill_seconds 3
  # Upper bound on how long an issued form stays submittable.
  @max_form_age_seconds 7_200

  def new(conn, _params) do
    render_form(conn, %{}, %{})
  end

  def create(conn, params) do
    # Validate first so a human with empty/invalid fields sees the real field
    # errors instead of a generic spam message; only fully valid submissions
    # are then subjected to the (silent) spam checks.
    case Bbh.Contact.validate(params) do
      {:error, errors} ->
        render_form(conn, params, errors)

      {:ok, data} ->
        case check_spam(conn, params) do
          :ok ->
            deliver(conn, data)

          {:spam, reason} ->
            Logger.warning("Contact form rejected as spam (#{reason})")

            conn
            |> put_flash(:error, "Spam-Schutz fehlgeschlagen. Bitte versuchen Sie es erneut.")
            |> render_form(params, %{})
        end
    end
  end

  defp deliver(conn, data) do
    case Bbh.Contact.deliver(data) do
      {:ok, _} ->
        conn
        |> put_flash(:info, "Vielen Dank! Ihre Nachricht wurde gesendet.")
        |> redirect(to: ~p"/kontakt")

      {:error, reason} ->
        Logger.error("Contact form delivery failed: #{inspect(reason)}")

        conn
        |> put_flash(
          :error,
          "Ihre Nachricht konnte nicht gesendet werden. Bitte versuchen Sie es später erneut."
        )
        |> render_form(data_to_params(data), %{})
    end
  end

  # Honeypot, then submit-timing, then the Altcha proof of work. Each layer is
  # independent so any one tripping is enough to reject.
  defp check_spam(conn, params) do
    cond do
      Bbh.Contact.honeypot_filled?(params) -> {:spam, "honeypot"}
      not timing_ok?(conn, params) -> {:spam, "timing"}
      Bbh.Altcha.enabled?() and not Bbh.Altcha.verify(params["altcha"]) -> {:spam, "altcha"}
      true -> :ok
    end
  end

  defp timing_ok?(conn, params) do
    case Phoenix.Token.verify(conn, @form_token_salt, params["form_ts"],
           max_age: @max_form_age_seconds
         ) do
      {:ok, issued_at} -> System.os_time(:second) - issued_at >= @min_fill_seconds
      {:error, _} -> false
    end
  end

  defp data_to_params(%{name: name, email: email, message: message}) do
    %{"name" => name, "email" => email, "message" => message}
  end

  defp render_form(conn, params, errors) do
    render(conn, :new,
      page_title: "Kontakt",
      params: params,
      errors: errors,
      form_token: Phoenix.Token.sign(conn, @form_token_salt, System.os_time(:second)),
      altcha: Bbh.Altcha.enabled?() && Bbh.Altcha.challenge()
    )
  end
end
