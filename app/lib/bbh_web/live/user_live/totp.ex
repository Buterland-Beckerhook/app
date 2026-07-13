defmodule BbhWeb.UserLive.Totp do
  @moduledoc "Set up or remove the TOTP second factor for the current user."
  use BbhWeb, :live_view

  alias Bbh.Accounts
  alias Bbh.Accounts.User

  @impl true
  def mount(_params, _session, socket) do
    {:ok, assign_state(socket, socket.assigns.current_scope.user)}
  end

  defp assign_state(socket, user) do
    if User.totp_enabled?(user) do
      assign(socket,
        page_title: "Zwei-Faktor",
        user: user,
        enabled: true,
        secret: nil,
        qr: nil,
        error: nil
      )
    else
      secret = Accounts.generate_totp_secret()
      qr = secret |> then(&Accounts.totp_uri(user, &1)) |> EQRCode.encode() |> EQRCode.svg(width: 200)

      assign(socket,
        page_title: "Zwei-Faktor",
        user: user,
        enabled: false,
        secret: secret,
        qr: qr,
        error: nil
      )
    end
  end

  @impl true
  def handle_event("enable", %{"code" => code}, socket) do
    if Accounts.valid_totp?(socket.assigns.secret, code) do
      {:ok, user} = Accounts.enable_totp(socket.assigns.user, socket.assigns.secret)
      {:noreply, socket |> put_flash(:info, "Zwei-Faktor aktiviert.") |> assign_state(user)}
    else
      {:noreply, assign(socket, :error, "Ungültiger Code. Bitte erneut versuchen.")}
    end
  end

  def handle_event("disable", _params, socket) do
    {:ok, user} = Accounts.disable_totp(socket.assigns.user)
    {:noreply, socket |> put_flash(:info, "Zwei-Faktor deaktiviert.") |> assign_state(user)}
  end

  def handle_event("regenerate", _params, socket) do
    {:noreply, assign_state(socket, socket.assigns.user)}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope} current_path="/users/2fa">
      <div class="mx-auto max-w-md">
        <.header>Zwei-Faktor-Authentifizierung</.header>

        <div :if={@enabled} class="mt-6 space-y-4">
          <div class="alert alert-success">Zwei-Faktor ist für dein Konto aktiviert.</div>
          <button
            class="btn btn-outline btn-error"
            phx-click="disable"
            data-confirm="Zwei-Faktor wirklich deaktivieren?"
          >
            Deaktivieren
          </button>
        </div>

        <div :if={!@enabled} class="mt-6 space-y-4">
          <p class="text-sm">
            Scanne den QR-Code mit einer Authenticator-App (z. B. Aegis, Google Authenticator)
            und gib anschließend den angezeigten Code ein.
          </p>
          <div class="w-fit rounded bg-white p-4">{Phoenix.HTML.raw(@qr)}</div>
          <p class="text-xs break-all text-base-content/60">
            Manuell: <span class="font-mono">{Base.encode32(@secret, padding: false)}</span>
          </p>
          <form phx-submit="enable" class="space-y-2">
            <input
              type="text"
              name="code"
              inputmode="numeric"
              maxlength="6"
              autocomplete="one-time-code"
              class="input input-bordered w-full text-center text-xl tracking-widest"
              placeholder="000000"
            />
            <p :if={@error} class="text-sm text-error">{@error}</p>
            <button class="btn btn-primary">Aktivieren</button>
          </form>
        </div>

        <div class="mt-8">
          <.link navigate={~p"/admin"} class="link">Zurück zur Verwaltung</.link>
        </div>
      </div>
    </Layouts.app>
    """
  end
end
