defmodule BbhWeb.UserLive.Login do
  use BbhWeb, :live_view

  alias Bbh.Accounts

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope}>
      <div class="mx-auto max-w-sm space-y-4">
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

        <div class="divider">or</div>

        <.form
          :let={f}
          for={@form}
          id="login_form_password"
          action={~p"/users/log-in"}
          phx-submit="submit_password"
          phx-trigger-action={@trigger_submit}
        >
          <.input
            readonly={!!@current_scope}
            field={f[:email]}
            type="email"
            label="Email"
            autocomplete="username"
            spellcheck="false"
            required
          />
          <.input
            field={@form[:password]}
            type="password"
            label="Password"
            autocomplete="current-password"
            spellcheck="false"
          />
          <.button class="btn btn-primary w-full" name={@form[:remember_me].name} value="true">
            Log in and stay logged in <span aria-hidden="true">→</span>
          </.button>
          <.button class="btn btn-primary btn-soft w-full mt-2">
            Log in only this time
          </.button>
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

    {:ok, assign(socket, form: form, trigger_submit: false, client_ip: connect_client_ip(socket))}
  end

  @impl true
  def handle_event("submit_password", _params, socket) do
    {:noreply, assign(socket, :trigger_submit, true)}
  end

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
