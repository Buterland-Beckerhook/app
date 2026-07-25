defmodule Bbh.Calendar.ShareNotifier do
  @moduledoc "Delivers calendar-share links by email."
  import Swoosh.Email

  alias Bbh.Mailer

  # Delivers the email using the application mailer.
  defp deliver(recipient, subject, body) do
    email =
      new()
      |> to(recipient)
      |> from({Mailer.sender_name(), Mailer.sender()})
      |> subject(subject)
      |> text_body(body)

    with {:ok, _metadata} <- Mailer.deliver_logged(email, "share") do
      {:ok, email}
    end
  end

  @doc "Deliver links to subscribe to a shared internal calendar."
  def deliver_calendar_share_instructions(recipient, calendar_label, webcal_url, https_url) do
    deliver(recipient, "Geteilter Kalender: #{calendar_label}", """

    ==============================

    Hallo,

    du wurdest eingeladen, den Kalender „#{calendar_label}“ zu abonnieren.

    Apple Kalender / Outlook — tippe auf diesen Link, um sofort zu abonnieren:

    #{webcal_url}

    Google Kalender / Android — öffne Google Kalender am Computer, dann
    „Weitere Kalender“ (+) → „Per URL“ und füge diese Adresse ein:

    #{https_url}

    Der Link ist persönlich für dich. Bitte gib ihn nicht weiter — er kann
    jederzeit widerrufen werden.

    ==============================
    """)
  end
end
