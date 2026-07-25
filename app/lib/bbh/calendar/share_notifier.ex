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

  @doc "Deliver a link to subscribe to a shared internal calendar."
  def deliver_calendar_share_instructions(recipient, calendar_label, url) do
    deliver(recipient, "Geteilter Kalender: #{calendar_label}", """

    ==============================

    Hallo,

    du wurdest eingeladen, den Kalender „#{calendar_label}“ zu abonnieren.

    Füge den folgenden Link in deiner Kalender-App als Abo hinzu
    (Apple Kalender, Google Kalender, Outlook …):

    #{url}

    Der Link ist persönlich für dich. Bitte gib ihn nicht weiter — er kann
    jederzeit widerrufen werden.

    ==============================
    """)
  end
end
