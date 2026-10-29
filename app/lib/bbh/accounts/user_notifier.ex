defmodule Bbh.Accounts.UserNotifier do
  import Swoosh.Email

  alias Bbh.Mailer
  alias Bbh.Accounts.User

  # Delivers the email using the application mailer.
  defp deliver(recipient, subject, body) do
    email =
      new()
      |> to(recipient)
      |> from({Mailer.sender_name(), Mailer.sender()})
      |> subject(subject)
      |> text_body(body)

    with {:ok, _metadata} <- Mailer.deliver_logged(email, "user") do
      {:ok, email}
    end
  end

  @doc """
  Deliver instructions to update a user email.
  """
  def deliver_update_email_instructions(user, url) do
    deliver(user.email, "E-Mail-Adresse ändern", """
    Hallo,

    für Ihr Konto auf buterland-beckerhook.de wurde eine Änderung der
    E-Mail-Adresse angefordert. Über diesen Link bestätigen Sie die neue Adresse:

    #{url}

    Wenn Sie diese Änderung nicht angefordert haben, können Sie diese E-Mail
    ignorieren.
    """)
  end

  @doc """
  Deliver instructions to log in with a magic link.
  """
  def deliver_login_instructions(user, url) do
    case user do
      %User{confirmed_at: nil} -> deliver_confirmation_instructions(user, url)
      _ -> deliver_magic_link_instructions(user, url)
    end
  end

  defp deliver_magic_link_instructions(user, url) do
    deliver(user.email, "Ihr Anmeldelink", """
    Hallo,

    über diesen Link melden Sie sich im internen Bereich von
    buterland-beckerhook.de an:

    #{url}

    Der Link ist nur kurze Zeit gültig und kann einmal verwendet werden.
    Wenn Sie keine Anmeldung angefordert haben, können Sie diese E-Mail ignorieren.
    """)
  end

  defp deliver_confirmation_instructions(user, url) do
    deliver(user.email, "Ihr Zugang zu buterland-beckerhook.de", """
    Hallo,

    für Sie wurde ein Zugang zum internen Bereich von buterland-beckerhook.de
    eingerichtet. Über diesen Link bestätigen Sie Ihr Konto und melden sich an:

    #{url}

    Der Link ist nur kurze Zeit gültig und kann einmal verwendet werden.
    Wenn Sie keinen Zugang erwartet haben, können Sie diese E-Mail ignorieren.
    """)
  end
end
