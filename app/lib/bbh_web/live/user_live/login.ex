defmodule BbhWeb.UserLive.Login do
  use BbhWeb, :live_view

  alias Bbh.Accounts
  alias Bbh.Accounts.Passkeys

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope}>
      <div
        id="login"
        phx-hook="Passkey"
        data-passkey-ceremony="get"
        data-passkey-options={@passkey_options}
        class="mx-auto max-w-sm space-y-4"
      >
        <div class="text-center">
          <.header>
            <p>Anmelden</p>
            <:subtitle>
              <%= if @current_scope do %>
                Bitte erneut anmelden, um sensible Aktionen durchzuführen.
              <% else %>
                Interner Bereich für Redakteure des Vereins.
              <% end %>
            </:subtitle>
          </.header>
        </div>

        <div :if={local_mail_adapter?()} class="alert alert-info">
          <.icon name="hero-information-circle" class="size-6 shrink-0" />
          <div>
            <p>You are running the local mail adapter.</p>
            <p>
              To see sent emails, visit <.link href="/dev/mailbox" class="underline">the mailbox page</.link>.
            </p>
          </div>
        </div>

        <.form
          :let={f}
          for={@form}
          id="login_form_magic"
          action={~p"/users/log-in"}
          phx-submit="submit_magic"
        >
          <.input
            readonly={!!@current_scope}
            field={f[:email]}
            type="email"
            label="Email"
            autocomplete="username"
            spellcheck="false"
            required
            phx-mounted={JS.focus()}
          />
          <.button class="btn btn-primary w-full">
            Log in with email <span aria-hidden="true">→</span>
          </.button>
        </.form>

        <div class="divider">oder</div>

        <button type="button" data-passkey-trigger class="btn btn-soft w-full">
          <.icon name="hero-key" class="size-5" /> Mit Passkey anmelden
        </button>

        <.form
          for={@passkey_form}
          id="passkey_login_form"
          action={~p"/users/log-in"}
          phx-trigger-action={@trigger_passkey}
          class="hidden"
        >
          <input type="hidden" name="user[passkey_token]" value={@passkey_token} />
          <input type="hidden" name="user[remember_me]" value="true" />
        </.form>
      </div>
    </Layouts.app>
    """
  end

  @impl true
  def mount(_params, _session, socket) do
    email =
      Phoenix.Flash.get(socket.assigns.flash, :email) ||
        get_in(socket.assigns, [:current_scope, Access.key(:user), Access.key(:email)])

    form = to_form(%{"email" => email}, as: "user")

    socket =
      assign(socket,
        form: form,
        passkey_form: to_form(%{}, as: "user"),
        passkey_challenge: nil,
        passkey_options: nil,
        passkey_token: nil,
        trigger_passkey: false,
        client_ip: connect_client_ip(socket)
      )

    # The passkey challenge is minted only on the connected mount and rendered
    # into the hook's data attribute, so the click handler can call WebAuthn
    # synchronously (see the Passkey hook in app.js). WebAuthn needs the live
    # socket anyway, so the button is inert in the dead render.
    {:ok, if(connected?(socket), do: assign_passkey_challenge(socket), else: socket)}
  end

  @impl true
  def handle_event("submit_magic", %{"user" => %{"email" => email}}, socket) do
    case BbhWeb.RateLimit.check("magic_send", socket.assigns.client_ip, 5, :timer.minutes(15)) do
      :ok ->
        if user = Accounts.get_user_by_email(email) do
          Accounts.deliver_login_instructions(
            user,
            &url(~p"/users/log-in/#{&1}")
          )
        end

        info =
          "If your email is in our system, you will receive instructions for logging in shortly."

        {:noreply,
         socket
         |> put_flash(:info, info)
         |> push_navigate(to: ~p"/users/log-in")}

      {:error, _retry_after} ->
        {:noreply,
         socket
         |> put_flash(:error, "Zu viele Anfragen. Bitte später erneut versuchen.")
         |> push_navigate(to: ~p"/users/log-in")}
    end
  end

  def handle_event(
        "passkey_login_assertion",
        _params,
        %{assigns: %{passkey_challenge: nil}} = socket
      ) do
    # No challenge in flight — the client pushed an assertion without one in the
    # assigns. Don't call into the ceremony with a nil challenge.
    {:noreply, put_flash(socket, :error, "Passkey-Anmeldung fehlgeschlagen.")}
  end

  def handle_event("passkey_login_assertion", params, socket) do
    # Rate-limit the actual verification attempt (the challenge itself is cheap
    # in-memory random bytes minted per connect, so gating it buys nothing).
    case BbhWeb.RateLimit.check("passkey_login", socket.assigns.client_ip, 10, :timer.minutes(5)) do
      :ok ->
        with {:ok, user} <-
               Passkeys.complete_authentication(socket.assigns.passkey_challenge, params),
             :ok <- same_user_on_reauth(socket, user) do
          token = Phoenix.Token.sign(BbhWeb.Endpoint, "passkey_session", user.id)

          {:noreply,
           assign(socket, passkey_challenge: nil, passkey_token: token, trigger_passkey: true)}
        else
          {:error, :wrong_user} ->
            {:noreply,
             socket
             |> assign_passkey_challenge()
             |> put_flash(:error, "Dieser Passkey gehört zu einem anderen Konto.")}

          {:error, _reason} ->
            {:noreply,
             socket
             |> assign_passkey_challenge()
             |> put_flash(:error, "Passkey-Anmeldung fehlgeschlagen.")}
        end

      {:error, _retry_after} ->
        {:noreply, put_flash(socket, :error, "Zu viele Versuche. Bitte später erneut versuchen.")}
    end
  end

  def handle_event("passkey_error", %{"message" => message}, socket) do
    {:noreply,
     socket
     |> assign_passkey_challenge()
     |> put_flash(:error, "Passkey abgebrochen: #{message}")}
  end

  # Mint a fresh authentication challenge and render it (plus the client options)
  # into the hook's data attribute. Called on connected mount and after every
  # failed/aborted attempt so a retry always has a live, single-use challenge.
  defp assign_passkey_challenge(socket) do
    challenge = Passkeys.new_authentication_challenge()

    assign(socket,
      passkey_challenge: challenge,
      passkey_options:
        Jason.encode!(%{
          challenge: Base.url_encode64(challenge.bytes, padding: false),
          rpId: BbhWeb.Endpoint.host(),
          userVerification: "required"
        })
    )
  end

  # This page doubles as the sudo re-auth page. When a user is already signed in,
  # a discoverable passkey could belong to a different account on the device —
  # refuse to silently swap the session to someone else.
  defp same_user_on_reauth(%{assigns: %{current_scope: %{user: %{id: id}}}}, %{id: user_id})
       when id != user_id,
       do: {:error, :wrong_user}

  defp same_user_on_reauth(_socket, _user), do: :ok

  defp local_mail_adapter? do
    Application.get_env(:bbh, Bbh.Mailer)[:adapter] == Swoosh.Adapters.Local
  end

  # Best-effort client IP from the socket connect info (trusted proxy sets
  # x-forwarded-for). Falls back to the peer address, then "unknown" on the
  # disconnected mount.
  defp connect_client_ip(socket) do
    forwarded =
      socket
      |> get_connect_info(:x_headers)
      |> List.wrap()
      |> Enum.find_value(fn
        {"x-forwarded-for", value} -> value |> String.split(",") |> List.first() |> String.trim()
        _ -> nil
      end)

    cond do
      is_binary(forwarded) ->
        forwarded

      true ->
        case get_connect_info(socket, :peer_data) do
          %{address: address} -> address |> :inet.ntoa() |> to_string()
          _ -> "unknown"
        end
    end
  end
end
