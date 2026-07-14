defmodule BbhWeb.ContactController do
  use BbhWeb, :controller

  require Logger

  def new(conn, _params) do
    render_form(conn, %{}, %{})
  end

  def create(conn, params) do
    cond do
      Bbh.Altcha.enabled?() and not Bbh.Altcha.verify(params["altcha"]) ->
        conn
        |> put_flash(:error, "Spam-Schutz fehlgeschlagen. Bitte versuchen Sie es erneut.")
        |> render_form(params, %{})

      true ->
        case Bbh.Contact.validate(params) do
          {:ok, data} ->
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
                |> render_form(params, %{})
            end

          {:error, errors} ->
            render_form(conn, params, errors)
        end
    end
  end

  defp render_form(conn, params, errors) do
    render(conn, :new,
      page_title: "Kontakt",
      params: params,
      errors: errors,
      altcha: Bbh.Altcha.enabled?() && Bbh.Altcha.challenge()
    )
  end
end
