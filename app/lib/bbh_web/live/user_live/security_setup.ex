defmodule BbhWeb.UserLive.SecuritySetup do
  @moduledoc """
  Post-login nudge shown to magic-link users who haven't set up a passkey
  and/or a second factor yet. Passkey-first: the passkey card comes first.
  Skippable — it's an encouragement, not a wall.
  """
  use BbhWeb, :live_view

  on_mount {BbhWeb.UserAuth, :require_authenticated}

  alias Bbh.Accounts.Passkeys
  alias Bbh.Accounts.User

  @impl true
  def mount(_params, _session, socket) do
    user = socket.assigns.current_scope.user
    needs_passkey = not Passkeys.has_passkey?(user)
    needs_totp = not User.totp_enabled?(user)

    if needs_passkey or needs_totp do
      {:ok,
       assign(socket,
         page_title: "Konto absichern",
         needs_passkey: needs_passkey,
         needs_totp: needs_totp
       )}
    else
      # Nothing to set up — don't show an empty page.
      {:ok, push_navigate(socket, to: ~p"/admin")}
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope}>
      <div class="mx-auto max-w-md space-y-4">
        <.header>
          Konto absichern
          <:subtitle>
            Melde dich künftig schneller und sicherer an. Du kannst das auch später
            in den Einstellungen erledigen.
          </:subtitle>
        </.header>

        <div :if={@needs_passkey} class="card border border-base-300 p-4">
          <p class="font-semibold">Passkey einrichten</p>
          <p class="text-sm text-base-content/70">
            Anmeldung ohne Passwort per Fingerabdruck, Gesichtserkennung oder Geräte-PIN.
            Empfohlen.
          </p>
          <.link navigate={~p"/admin/einstellungen/passkeys"} class="btn btn-primary mt-3">
            <.icon name="hero-key" class="size-5" /> Passkey hinzufügen
          </.link>
        </div>

        <div :if={@needs_totp} class="card border border-base-300 p-4">
          <p class="font-semibold">Zwei-Faktor (2FA) einrichten</p>
          <p class="text-sm text-base-content/70">
            Schützt die Anmeldung per E-Mail-Link mit einem zusätzlichen Code aus einer
            Authenticator-App.
          </p>
          <.link navigate={~p"/admin/einstellungen/2fa"} class="btn btn-soft mt-3">
            <.icon name="hero-shield-check" class="size-5" /> 2FA einrichten
          </.link>
        </div>

        <div class="pt-2 text-center">
          <.link navigate={~p"/admin"} class="link link-hover text-sm">
            Später erinnern – weiter zur Verwaltung
          </.link>
        </div>
      </div>
    </Layouts.app>
    """
  end
end
