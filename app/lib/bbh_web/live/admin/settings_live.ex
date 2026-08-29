defmodule BbhWeb.Admin.SettingsLive do
  @moduledoc """
  Account settings shown as a modal over the admin chrome. Consolidates the
  email-change, passkey management, and TOTP (2FA) screens into one LiveView
  with in-place sections switched via `live_patch` (`@live_action`):

    * `:account`  — `/admin/einstellungen`
    * `:passkeys` — `/admin/einstellungen/passkeys`
    * `:totp`     — `/admin/einstellungen/2fa`
    * `:tokens`   — `/admin/einstellungen/tokens`

  Closing the modal returns to `/admin`.
  """
  use BbhWeb, :live_view

  # Changing the email or a sign-in method is a sensitive account action —
  # require a recent re-authentication (sudo mode) on top of the live_session's
  # staff check.
  on_mount {BbhWeb.UserAuth, :require_sudo_mode}

  alias Bbh.Accounts
  alias Bbh.Accounts.Passkeys
  alias Bbh.Accounts.User
  alias Bbh.ApiTokens
  alias BbhWeb.MCP.Args

  @rp_name "Buterland-Beckerhook"

  @impl true
  def mount(%{"token" => token}, _session, socket) do
    socket =
      case Accounts.update_user_email(socket.assigns.current_scope.user, token) do
        {:ok, _user} ->
          put_flash(socket, :info, "Email changed successfully.")

        {:error, _} ->
          put_flash(socket, :error, "Email change link is invalid or it has expired.")
      end

    {:ok, push_navigate(socket, to: ~p"/admin/einstellungen")}
  end

  def mount(_params, _session, socket) do
    user = socket.assigns.current_scope.user
    email_changeset = Accounts.change_user_email(user, %{}, validate_unique: false)

    socket =
      socket
      |> assign(:email_form, to_form(email_changeset))
      |> assign(challenge: nil, passkey_options: nil, error: nil)
      |> assign(enabled: false, secret: nil, qr: nil)
      |> assign(tokens: [], new_token: nil)

    {:ok, socket}
  end

  @impl true
  def handle_params(_params, _uri, socket) do
    {:noreply, apply_action(socket, socket.assigns.live_action)}
  end

  defp apply_action(socket, :passkeys) do
    user = socket.assigns.current_scope.user

    socket =
      assign(socket, page_title: "Passkeys", passkeys: Passkeys.list_passkeys(user), error: nil)

    # Mint the challenge on the connected mount and render it into the hook's
    # data attribute, so the "Passkey hinzufügen" submit calls WebAuthn
    # synchronously and Safari keeps the user-activation window (see app.js).
    if connected?(socket), do: assign_registration_challenge(socket), else: socket
  end

  defp apply_action(socket, :tokens) do
    assign(socket,
      page_title: "Zugriffstoken",
      tokens: ApiTokens.list_pats(socket.assigns.current_scope.user),
      # Drop any freshly minted plaintext: it is shown once, on the render that follows
      # its creation, and must not survive navigating back to this section.
      new_token: nil,
      error: nil
    )
  end

  defp apply_action(socket, :totp) do
    assign_totp_state(socket, socket.assigns.current_scope.user)
  end

  defp apply_action(socket, _account) do
    assign(socket, page_title: "Einstellungen")
  end

  ## Account (email) ---------------------------------------------------------

  @impl true
  def handle_event("validate_email", %{"user" => user_params}, socket) do
    email_form =
      socket.assigns.current_scope.user
      |> Accounts.change_user_email(user_params, validate_unique: false)
      |> Map.put(:action, :validate)
      |> to_form()

    {:noreply, assign(socket, email_form: email_form)}
  end

  def handle_event("update_email", %{"user" => user_params}, socket) do
    user = socket.assigns.current_scope.user
    true = Accounts.sudo_mode?(user)

    case Accounts.change_user_email(user, user_params) do
      %{valid?: true} = changeset ->
        Accounts.deliver_user_update_email_instructions(
          Ecto.Changeset.apply_action!(changeset, :insert),
          user.email,
          &url(~p"/admin/einstellungen/confirm-email/#{&1}")
        )

        info = "A link to confirm your email change has been sent to the new address."
        {:noreply, put_flash(socket, :info, info)}

      changeset ->
        {:noreply, assign(socket, :email_form, to_form(changeset, action: :insert))}
    end
  end

  ## Access tokens (MCP) -----------------------------------------------------

  def handle_event("create_token", %{"name" => name, "access" => access}, socket) do
    user = socket.assigns.current_scope.user
    # `on_mount :require_sudo_mode` already gates this LiveView; assert it here too, the
    # way update_email does, so minting a credential can never ride on a stale mount.
    true = Accounts.sudo_mode?(user)

    case ApiTokens.create_pat(user, name, scopes_for(access)) do
      {:ok, plaintext, _token} ->
        {:noreply,
         socket
         |> assign(new_token: plaintext, tokens: ApiTokens.list_pats(user), error: nil)}

      {:error, changeset} ->
        {:noreply, assign(socket, error: Args.errors(changeset))}
    end
  end

  def handle_event("revoke_token", %{"id" => id}, socket) do
    user = socket.assigns.current_scope.user

    case ApiTokens.get_for_user(user, id) do
      nil ->
        {:noreply, put_flash(socket, :error, "Token nicht gefunden.")}

      token ->
        {:ok, _} = ApiTokens.revoke(token)

        # Deliberately does NOT touch `new_token`: revoking an old token must not wipe a
        # plaintext that was just minted and not yet copied — it is unrecoverable.
        # Clearing on leaving the section is `apply_action(:tokens)`'s job.
        {:noreply,
         socket
         |> assign(tokens: ApiTokens.list_pats(user))
         |> put_flash(:info, "Token widerrufen.")}
    end
  end

  ## TOTP (2FA) --------------------------------------------------------------

  def handle_event("enable", %{"code" => code}, socket) do
    if Accounts.valid_totp?(socket.assigns.secret, code) do
      {:ok, user} = Accounts.enable_totp(socket.assigns.current_scope.user, socket.assigns.secret)

      {:noreply,
       socket
       |> update_current_user(user)
       |> put_flash(:info, "Zwei-Faktor aktiviert.")
       |> assign_totp_state(user)}
    else
      {:noreply, assign(socket, :error, "Ungültiger Code. Bitte erneut versuchen.")}
    end
  end

  def handle_event("disable", _params, socket) do
    {:ok, user} = Accounts.disable_totp(socket.assigns.current_scope.user)

    {:noreply,
     socket
     |> update_current_user(user)
     |> put_flash(:info, "Zwei-Faktor deaktiviert.")
     |> assign_totp_state(user)}
  end

  def handle_event("regenerate", _params, socket) do
    {:noreply, assign_totp_state(socket, socket.assigns.current_scope.user)}
  end

  ## Passkeys ----------------------------------------------------------------

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

  ## Modal -------------------------------------------------------------------

  def handle_event("close", _params, socket) do
    {:noreply, push_navigate(socket, to: ~p"/admin")}
  end

  ## Helpers -----------------------------------------------------------------

  # "Nur Lesen" is the narrower grant; mcp:write implies mcp:read on the server, but the
  # token records both so the admin list shows what was actually granted.
  defp scopes_for("ro"), do: ["mcp:read"]
  defp scopes_for(_rw), do: ["mcp:read", "mcp:write"]

  defp update_current_user(socket, user) do
    assign(socket, :current_scope, %{socket.assigns.current_scope | user: user})
  end

  defp assign_totp_state(socket, user) do
    if User.totp_enabled?(user) do
      assign(socket,
        page_title: "Zwei-Faktor",
        enabled: true,
        secret: nil,
        qr: nil,
        error: nil
      )
    else
      secret = Accounts.generate_totp_secret()

      qr =
        secret
        |> then(&Accounts.totp_uri(user, &1))
        |> EQRCode.encode()
        |> EQRCode.svg(width: 200)

      assign(socket,
        page_title: "Zwei-Faktor",
        enabled: false,
        secret: secret,
        qr: qr,
        error: nil
      )
    end
  end

  # Mint a fresh registration challenge and render it (plus the create options)
  # into the hook's data attribute. Called on entering the passkeys section and
  # after every completed/aborted attempt so a follow-up registration always has
  # a live, single-use challenge.
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

  ## Render ------------------------------------------------------------------

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.admin flash={@flash} current_scope={@current_scope} active={nil}>
      <div
        class="fixed inset-0 z-50 flex items-end justify-center bg-black/50 p-4 sm:items-center"
        phx-window-keydown="close"
        phx-key="Escape"
      >
        <div class="w-full max-w-lg rounded-t-box bg-base-100 p-5 shadow-xl sm:rounded-box">
          <div class="mb-4 flex items-center justify-between">
            <h2 class="text-lg font-semibold">Einstellungen</h2>
            <.link navigate={~p"/admin"} class="btn btn-ghost btn-sm" aria-label="Schließen">
              ✕
            </.link>
          </div>

          <div role="tablist" aria-label="Einstellungen" class="tabs tabs-border mb-4">
            <.link
              patch={~p"/admin/einstellungen"}
              role="tab"
              aria-selected={to_string(@live_action == :account)}
              class={["tab", @live_action == :account && "tab-active"]}
            >
              Account
            </.link>
            <.link
              patch={~p"/admin/einstellungen/passkeys"}
              role="tab"
              aria-selected={to_string(@live_action == :passkeys)}
              class={["tab", @live_action == :passkeys && "tab-active"]}
            >
              Passkeys
            </.link>
            <.link
              patch={~p"/admin/einstellungen/2fa"}
              role="tab"
              aria-selected={to_string(@live_action == :totp)}
              class={["tab", @live_action == :totp && "tab-active"]}
            >
              2FA
            </.link>
            <.link
              patch={~p"/admin/einstellungen/tokens"}
              role="tab"
              aria-selected={to_string(@live_action == :tokens)}
              class={["tab", @live_action == :tokens && "tab-active"]}
            >
              Token
            </.link>
          </div>

          <.account_section :if={@live_action == :account} email_form={@email_form} />
          <.passkeys_section
            :if={@live_action == :passkeys}
            passkeys={@passkeys}
            passkey_options={@passkey_options}
            error={@error}
          />
          <.totp_section
            :if={@live_action == :totp}
            enabled={@enabled}
            secret={@secret}
            qr={@qr}
            error={@error}
          />
          <.tokens_section
            :if={@live_action == :tokens}
            tokens={@tokens}
            new_token={@new_token}
            error={@error}
          />
        </div>
      </div>
    </Layouts.admin>
    """
  end

  attr :email_form, :map, required: true

  defp account_section(assigns) do
    ~H"""
    <div>
      <.header>
        Account
        <:subtitle>Verwalte deine E-Mail-Adresse.</:subtitle>
      </.header>

      <.form
        for={@email_form}
        id="email_form"
        phx-submit="update_email"
        phx-change="validate_email"
        class="mt-4"
      >
        <.input
          field={@email_form[:email]}
          type="email"
          label="Email"
          autocomplete="username"
          spellcheck="false"
          required
        />
        <.button variant="primary" phx-disable-with="Changing...">Change Email</.button>
      </.form>

      <div class="mt-6 border-t border-base-300 pt-4">
        <p class="mb-2 text-sm text-base-content/70">
          Meldet dich auf allen Geräten ab – auch in dieser Sitzung.
        </p>
        <.link
          href={~p"/users/log-out-all"}
          method="delete"
          data-confirm="Auf allen Geräten (auch hier) abmelden?"
          class="btn btn-outline btn-error btn-sm"
        >
          Auf allen Geräten abmelden
        </.link>
      </div>
    </div>
    """
  end

  attr :passkeys, :list, required: true
  attr :passkey_options, :string, required: true
  attr :error, :string, required: true

  defp passkeys_section(assigns) do
    ~H"""
    <div
      id="passkeys"
      phx-hook="Passkey"
      data-passkey-ceremony="create"
      data-passkey-options={@passkey_options}
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
    </div>
    """
  end

  attr :enabled, :boolean, required: true
  attr :secret, :any, required: true
  attr :qr, :any, required: true
  attr :error, :string, required: true

  defp totp_section(assigns) do
    ~H"""
    <div>
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
          Manuell:
          <span id="totp-secret" class="font-mono">{Base.encode32(@secret, padding: false)}</span>
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
    </div>
    """
  end

  attr :tokens, :list, required: true
  attr :new_token, :string, required: true
  attr :error, :string, required: true

  defp tokens_section(assigns) do
    ~H"""
    <div>
      <.header>
        Zugriffstoken
        <:subtitle>
          Für KI-Assistenten (MCP), z. B. um unterwegs einen Artikel zu diktieren.
          Ein Token darf genau das, was du selbst darfst – aber niemals löschen.
        </:subtitle>
      </.header>

      <div :if={@new_token} class="alert alert-success mt-6 flex-col items-start gap-2">
        <p class="font-medium">Token erstellt – jetzt kopieren!</p>
        <input
          type="text"
          readonly
          value={@new_token}
          aria-label="Neues Zugriffstoken"
          class="input input-sm w-full bg-base-100 font-mono text-xs"
        />
        <p class="text-xs">
          Er wird nur dieses eine Mal angezeigt. Danach ist er nicht mehr auslesbar.
        </p>
      </div>

      <div :if={@tokens == []} class="alert alert-info mt-6">
        Du hast noch kein Zugriffstoken.
      </div>

      <ul :if={@tokens != []} class="mt-6 divide-y divide-base-300">
        <li :for={token <- @tokens} class="flex items-center justify-between gap-3 py-3">
          <div class="min-w-0">
            <p class="truncate font-medium">{token.name}</p>
            <p class="text-xs text-base-content/60">
              {if "mcp:write" in token.scopes, do: "Lesen und Schreiben", else: "Nur Lesen"} · erstellt {Calendar.strftime(
                token.inserted_at,
                "%d.%m.%Y"
              )}
              <span :if={token.expires_at}>
                · gültig bis {Calendar.strftime(token.expires_at, "%d.%m.%Y")}
              </span>
              <span :if={token.last_used_at}>
                · zuletzt genutzt {Calendar.strftime(token.last_used_at, "%d.%m.%Y")}
              </span>
              <span :if={is_nil(token.last_used_at)}>· noch nie genutzt</span>
            </p>
          </div>
          <button
            class="btn btn-sm btn-outline btn-error shrink-0"
            phx-click="revoke_token"
            phx-value-id={token.id}
            data-confirm="Dieses Token wirklich widerrufen? Verbundene Apps verlieren sofort den Zugriff."
          >
            Widerrufen
          </button>
        </li>
      </ul>

      <form id="token_form" phx-submit="create_token" class="mt-6 space-y-2">
        <.input
          type="text"
          name="name"
          value=""
          label="Name des Tokens"
          placeholder="z. B. Claude auf dem iPhone"
          maxlength="100"
          required
        />
        <.input
          type="select"
          name="access"
          value="rw"
          label="Berechtigung"
          options={[{"Lesen und Schreiben", "rw"}, {"Nur Lesen", "ro"}]}
        />
        <p :if={@error} class="text-sm text-error">{@error}</p>
        <.button class="btn btn-primary w-full">
          <.icon name="hero-key" class="size-5" /> Token erstellen
        </.button>
      </form>
    </div>
    """
  end
end
