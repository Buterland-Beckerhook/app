defmodule BbhWeb.Admin.SiteSettingsLive do
  @moduledoc "Admin-only site settings: homepage notice banner and push quiet hours."
  use BbhWeb, :live_view

  alias Bbh.Settings

  @hours for h <- 0..23, do: {String.pad_leading(Integer.to_string(h), 2, "0") <> ":00", h}

  @impl true
  def mount(_params, _session, socket) do
    settings = Settings.get()

    {:ok,
     socket
     |> assign(page_title: "Website", hours: @hours)
     |> assign_form(Settings.change(settings))}
  end

  @impl true
  def handle_event("validate", %{"site_settings" => params}, socket) do
    changeset =
      Settings.get()
      |> Settings.change(params)
      |> Map.put(:action, :validate)

    {:noreply, assign_form(socket, changeset)}
  end

  def handle_event("save", %{"site_settings" => params}, socket) do
    case Settings.update(params) do
      {:ok, settings} ->
        {:noreply,
         socket
         |> put_flash(:info, "Einstellungen gespeichert.")
         |> assign_form(Settings.change(settings))}

      {:error, changeset} ->
        {:noreply, assign_form(socket, changeset)}
    end
  end

  defp assign_form(socket, changeset),
    do: assign(socket, :form, to_form(changeset, as: "site_settings"))

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.admin flash={@flash} current_scope={@current_scope} active={:site_settings}>
      <.header>
        Website
        <:subtitle>Hinweis auf der Startseite und Ruhezeiten für Push-Nachrichten.</:subtitle>
      </.header>

      <.form
        for={@form}
        id="site-settings-form"
        phx-change="validate"
        phx-submit="save"
        class="mt-6 space-y-8"
      >
        <fieldset class="rounded-box border border-base-300 p-4">
          <legend class="px-1 text-sm font-medium">Hinweis auf der Startseite</legend>
          <.input
            field={@form[:home_notice_enabled]}
            type="checkbox"
            label="Hinweis anzeigen"
          />
          <.input
            field={@form[:home_notice_text]}
            type="textarea"
            label="Text"
            rows="3"
            placeholder="z. B. Das Sommerfest fällt wegen des Wetters aus."
          />
          <p class="mt-1 text-sm text-base-content/60">
            Erscheint als Banner oben auf der Startseite. Einfache Links sind erlaubt.
          </p>
        </fieldset>

        <fieldset class="rounded-box border border-base-300 p-4">
          <legend class="px-1 text-sm font-medium">Ruhezeiten (keine Push-Nachrichten)</legend>
          <.input
            field={@form[:quiet_hours_enabled]}
            type="checkbox"
            label="Nachts keine Push-Nachrichten senden"
          />
          <div class="mt-3 grid gap-4 sm:grid-cols-2">
            <.input field={@form[:quiet_hours_start]} type="select" label="Von" options={@hours} />
            <.input field={@form[:quiet_hours_end]} type="select" label="Bis" options={@hours} />
          </div>
          <p class="mt-1 text-sm text-base-content/60">
            Fällige Erinnerungen und Ankündigungen werden zurückgehalten und nach dem Fenster
            automatisch nachgeholt. Zeiten in {Bbh.Time.time_zone()}.
          </p>
        </fieldset>

        <div class="flex gap-2">
          <.button variant="primary" phx-disable-with="Speichern…">Speichern</.button>
        </div>
      </.form>
    </Layouts.admin>
    """
  end
end
