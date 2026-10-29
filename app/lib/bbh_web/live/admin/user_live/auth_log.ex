defmodule BbhWeb.Admin.UserLive.AuthLog do
  @moduledoc "Admin-only: one user's login log (`Bbh.Accounts.AuthLog`)."
  use BbhWeb, :live_view

  alias Bbh.Accounts
  alias Bbh.Accounts.AuthLog

  @event_labels %{
    "magic_link_sent" => "Anmeldelink angefordert",
    "login_succeeded" => "Angemeldet",
    "login_failed" => "Anmeldung fehlgeschlagen",
    "totp_failed" => "Falscher 2FA-Code",
    "passkey_failed" => "Passkey fehlgeschlagen",
    "logged_out" => "Abgemeldet"
  }

  @method_labels %{
    "passkey" => "Passkey",
    "magic_link" => "Anmeldelink",
    "magic_link_totp" => "Anmeldelink + 2FA"
  }

  @failures ~w(login_failed totp_failed passkey_failed)

  @impl true
  def mount(%{"id" => id}, _session, socket) do
    user = Accounts.get_user!(id)

    {:ok,
     assign(socket,
       page_title: "Anmeldungen · #{user.email}",
       user: user,
       events: AuthLog.list_for_user(user),
       retention_days: AuthLog.retention_days()
     )}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.admin flash={@flash} current_scope={@current_scope} active={:users}>
      <.header>
        Anmeldungen
        <:subtitle>
          {@user.email} · die letzten {@retention_days} Tage, neueste zuerst.
        </:subtitle>
        <:actions>
          <.button navigate={~p"/admin/benutzer"}>Zurück</.button>
        </:actions>
      </.header>

      <p :if={@events == []} class="mt-6 text-base-content/60">Keine Einträge.</p>

      <.table :if={@events != []} id="auth-events" rows={@events}>
        <:col :let={e} label="Zeit">{local_time(e.inserted_at)}</:col>
        <:col :let={e} label="Ereignis">
          <span class={failure?(e.event) && "text-error"}>{event_label(e.event)}</span>
        </:col>
        <:col :let={e} label="Methode">{method_label(e.method)}</:col>
        <:col :let={e} label="IP"><span class="font-mono text-sm">{e.ip}</span></:col>
        <:col :let={e} label="Browser">
          <span class="block max-w-xs truncate text-sm" title={e.user_agent}>{e.user_agent}</span>
        </:col>
      </.table>
    </Layouts.admin>
    """
  end

  defp failure?(event), do: event in @failures

  defp event_label(event), do: Map.get(@event_labels, event, event)
  defp method_label(nil), do: "–"
  defp method_label(method), do: Map.get(@method_labels, method, method)

  defp local_time(dt),
    do: dt |> DateTime.shift_zone!(Bbh.Time.time_zone()) |> BbhWeb.Format.de_short_datetime()
end
