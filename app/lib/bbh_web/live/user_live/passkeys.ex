defmodule BbhWeb.UserLive.Passkeys do
  @moduledoc "Register and manage WebAuthn passkeys for the current user."
  use BbhWeb, :live_view

  # Adding/removing a login credential is a sensitive account action — require a
  # recent re-authentication (sudo mode) on top of the live_session's auth check.
  on_mount {BbhWeb.UserAuth, :require_sudo_mode}

  alias Bbh.Accounts.Passkeys

  @rp_name "Buterland-Beckerhook"

  @impl true
  def mount(_params, _session, socket) do
    user = socket.assigns.current_scope.user

    socket =
      assign(socket,
        page_title: "Passkeys",
        passkeys: Passkeys.list_passkeys(user),
        challenge: nil,
        passkey_options: nil,
        error: nil
      )

    # Mint the challenge on the connected mount and render it into the hook's
    # data attribute, so the "Passkey hinzufügen" submit calls WebAuthn
    # synchronously and Safari keeps the user-activation window (see app.js).
    {:ok, if(connected?(socket), do: assign_registration_challenge(socket), else: socket)}
  end

  @impl true
  def handle_event("nickname_blank", _params, socket) do
    # The client refused to open the authenticator because the name was empty.
    {:noreply, assign(socket, :error, "Bitte einen Namen für den Passkey angeben.")}
  end

  def handle_event("register_credential", _params, %{assigns: %{challenge: nil}} = socket) do
    # A credential was pushed without an in-flight challenge — ignore it rather
    # than calling the ceremony with a nil challenge.
    {:noreply, put_flash(socket, :error, "Passkey konnte nicht registriert werden.")}
  end

  def handle_event("register_credential", params, socket) do
    user = socket.assigns.current_scope.user
    nickname = String.trim(params["nickname"] || "")

    if nickname == "" do
      {:noreply, assign(socket, :error, "Bitte einen Namen für den Passkey angeben.")}
    else
      case Passkeys.complete_registration(user, socket.assigns.challenge, params, nickname) do
        {:ok, _passkey} ->
          {:noreply,
           socket
           |> assign(passkeys: Passkeys.list_passkeys(user), error: nil)
           |> assign_registration_challenge()
           |> put_flash(:info, "Passkey hinzugefügt.")}

        {:error, _reason} ->
          {:noreply,
           socket
           |> assign_registration_challenge()
           |> put_flash(:error, "Passkey konnte nicht registriert werden.")}
      end
    end
  end

  def handle_event("delete", %{"id" => id}, socket) do
    user = socket.assigns.current_scope.user
    _ = Passkeys.delete_passkey(user, id)

    {:noreply,
     socket
     |> assign(:passkeys, Passkeys.list_passkeys(user))
     |> put_flash(:info, "Passkey entfernt.")}
  end

  def handle_event("passkey_error", %{"message" => message}, socket) do
    {:noreply,
     socket
     |> assign_registration_challenge()
     |> put_flash(:error, "Passkey abgebrochen: #{message}")}
  end

  # Mint a fresh registration challenge and render it (plus the create options)
  # into the hook's data attribute. Called on connected mount and after every
  # completed/aborted attempt so a follow-up registration always has a live,
  # single-use challenge.
  defp assign_registration_challenge(socket) do
    user = socket.assigns.current_scope.user
    challenge = Passkeys.new_registration_challenge(user)

    options =
      Jason.encode!(%{
        challenge: Base.url_encode64(challenge.bytes, padding: false),
        rp: %{id: BbhWeb.Endpoint.host(), name: @rp_name},
        user: %{
          id: Base.url_encode64(user.id, padding: false),
          name: user.email,
          displayName: user.email
        },
        excludeCredentials:
          Enum.map(Passkeys.credential_ids(user), &Base.url_encode64(&1, padding: false)),
        userVerification: "required",
        residentKey: "required"
      })

    assign(socket, challenge: challenge, passkey_options: options)
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope} current_path="/users/passkeys">
      <div
        id="passkeys"
        phx-hook="Passkey"
        data-passkey-ceremony="create"
        data-passkey-options={@passkey_options}
        class="mx-auto max-w-md"
      >
        <.header>
          Passkeys
          <:subtitle>
            Melde dich künftig ohne Passwort an – mit Fingerabdruck, Gesichtserkennung
            oder der PIN deines Geräts.
          </:subtitle>
        </.header>

        <div :if={@passkeys == []} class="alert alert-info mt-6">
          Du hast noch keinen Passkey eingerichtet.
        </div>

        <ul :if={@passkeys != []} class="mt-6 divide-y divide-base-300">
          <li :for={passkey <- @passkeys} class="flex items-center justify-between py-3">
            <div>
              <p class="font-medium">{passkey.nickname}</p>
              <p class="text-xs text-base-content/60">
                Erstellt am {Calendar.strftime(passkey.inserted_at, "%d.%m.%Y")}
                <span :if={passkey.last_used_at}>
                  · zuletzt genutzt {Calendar.strftime(passkey.last_used_at, "%d.%m.%Y")}
                </span>
              </p>
            </div>
            <button
              class="btn btn-sm btn-outline btn-error"
              phx-click="delete"
              phx-value-id={passkey.id}
              data-confirm="Diesen Passkey wirklich entfernen?"
            >
              Entfernen
            </button>
          </li>
        </ul>

        <form data-passkey-trigger class="mt-6 space-y-2">
          <.input
            type="text"
            name="nickname"
            value=""
            label="Name des Passkeys"
            placeholder="z. B. iPhone, YubiKey, Laptop"
            maxlength="60"
          />
          <p :if={@error} class="text-sm text-error">{@error}</p>
          <.button class="btn btn-primary w-full">
            <.icon name="hero-key" class="size-5" /> Passkey hinzufügen
          </.button>
        </form>

        <div class="mt-8">
          <.link navigate={~p"/users/settings"} class="link">Zurück zu den Einstellungen</.link>
        </div>
      </div>
    </Layouts.app>
    """
  end
end
