defmodule Bbh.Contact do
  @moduledoc "Contact-form validation and delivery."
  import Swoosh.Email
  alias Bbh.Mailer

  @type params :: %{optional(String.t()) => String.t()}

  @doc """
  Validate the contact params. Returns `{:ok, data}` or `{:error, errors}` where
  `errors` is a map of field => message.
  """
  def validate(params) do
    name = params |> Map.get("name", "") |> String.trim()
    email = params |> Map.get("email", "") |> String.trim()
    message = params |> Map.get("message", "") |> String.trim()
    consent = params["privacy"] in ["true", "on", "1"]

    errors =
      %{}
      |> put_if(name == "", :name, "Bitte geben Sie Ihren Namen an.")
      |> put_if(not valid_email?(email), :email, "Bitte geben Sie eine gültige E-Mail-Adresse an.")
      |> put_if(message == "", :message, "Bitte geben Sie eine Nachricht ein.")
      |> put_if(not consent, :privacy, "Bitte stimmen Sie der Datenschutzerklärung zu.")

    if errors == %{},
      do: {:ok, %{name: name, email: email, message: message}},
      else: {:error, errors}
  end

  @doc "Send the validated contact message to the club inbox."
  def deliver(%{name: name, email: email, message: message}) do
    new()
    |> to(recipient())
    |> from({"Website Kontaktformular", sender()})
    |> reply_to({name, email})
    |> subject("Kontaktanfrage von #{name}")
    |> text_body("Von: #{name} <#{email}>\n\n#{message}\n")
    |> Mailer.deliver()
  end

  defp valid_email?(email), do: Regex.match?(~r/^[^\s@]+@[^\s@]+\.[^\s@]+$/, email)

  defp put_if(map, true, key, msg), do: Map.put(map, key, msg)
  defp put_if(map, false, _key, _msg), do: map

  defp recipient, do: Application.get_env(:bbh, :contact_recipient, "info@buterland-beckerhook.de")
  defp sender, do: Application.get_env(:bbh, :contact_sender, "noreply@buterland-beckerhook.de")
end
