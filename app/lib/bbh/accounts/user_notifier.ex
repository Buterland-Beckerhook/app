defmodule Bbh.Accounts.UserNotifier do
  import Swoosh.Email

  alias Bbh.Mailer
  alias Bbh.Accounts.User

  # Delivers the email using the application mailer.
  defp deliver(recipient, subject, body) do
    email =
      new()
      |> to(recipient)
      |> from({"Bbh", sender()})
      |> subject(subject)
      |> text_body(body)

    with {:ok, _metadata} <- Mailer.deliver_logged(email, "user") do
      {:ok, email}
    end
  end

  # The authenticated SMTP sender. Shared with the contact form via the same
  # `:contact_sender` config so account mail (login, confirmation, email
  # changes) goes out as an address the SMTP user owns — otherwise the relay
  # rejects it with `reject_sender_login_mismatch`.
  defp sender, do: Application.get_env(:bbh, :contact_sender, "noreply@buterland-beckerhook.de")

  @doc """
  Deliver instructions to update a user email.
  """
  def deliver_update_email_instructions(user, url) do
    deliver(user.email, "Update email instructions", """

    ==============================

    Hi #{user.email},

    You can change your email by visiting the URL below:

    #{url}

    If you didn't request this change, please ignore this.

    ==============================
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
    deliver(user.email, "Log in instructions", """

    ==============================

    Hi #{user.email},

    You can log into your account by visiting the URL below:

    #{url}

    If you didn't request this email, please ignore this.

    ==============================
    """)
  end

  defp deliver_confirmation_instructions(user, url) do
    deliver(user.email, "Confirmation instructions", """

    ==============================

    Hi #{user.email},

    You can confirm your account by visiting the URL below:

    #{url}

    If you didn't create an account with us, please ignore this.

    ==============================
    """)
  end
end
