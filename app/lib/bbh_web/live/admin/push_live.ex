defmodule BbhWeb.Admin.PushLive do
  @moduledoc """
  Admin-only push tools: compose and send an ad-hoc notification, and review the
  stored subscriptions (with error counts) with the option to delete them.
  """
  use BbhWeb, :live_view

  alias Bbh.Notifications

  @categories [{"Termine", "termine"}, {"News", "news"}, {"Alle Abonnenten", "all"}]

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign(page_title: "Push", categories: @categories)
     |> assign(send_form: to_form(default_send(), as: "push"))
     |> load_subscriptions()}
  end

  @impl true
  def handle_event("send", %{"push" => params}, socket) do
    %{"category" => cat, "title" => title, "body" => body} = params
    url = if params["url"] in [nil, ""], do: BbhWeb.Endpoint.url(), else: params["url"]

    cond do
      String.trim(title) == "" or String.trim(body) == "" ->
        {:noreply, put_flash(socket, :error, "Titel und Text dürfen nicht leer sein.")}

      cat not in Enum.map(@categories, &elem(&1, 1)) ->
        {:noreply, put_flash(socket, :error, "Ungültige Kategorie.")}

      true ->
        payload = %{title: title, body: body, url: url}
        Notifications.dispatch(fn -> Notifications.send_manual(cat, payload) end)

        {:noreply,
         socket
         |> put_flash(:info, "Push-Nachricht wird gesendet.")
         |> assign(send_form: to_form(default_send(), as: "push"))}
    end
  end

  def handle_event("delete", %{"id" => id}, socket) do
    Notifications.delete_subscription(id)
    {:noreply, socket |> put_flash(:info, "Abo gelöscht.") |> load_subscriptions()}
  end

  defp default_send, do: %{"category" => "termine", "title" => "", "body" => "", "url" => ""}

  defp load_subscriptions(socket) do
    subs = Notifications.list_subscriptions()
    assign(socket, subscriptions: subs, sub_count: length(subs))
  end

  # Endpoints are secret URLs; show only the push-service host in the overview.
  defp endpoint_host(endpoint) do
    case URI.parse(endpoint) do
      %URI{host: host} when is_binary(host) -> host
      _ -> "—"
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.admin flash={@flash} current_scope={@current_scope} active={:push}>
      <.header>
        Push
        <:subtitle>
          Nachricht an Abonnenten senden und Abos verwalten (nur Administratoren).
        </:subtitle>
      </.header>

      <div :if={Bbh.Settings.quiet_now?()} class="alert alert-warning mt-6">
        <.icon name="hero-moon" class="size-5" />
        <span>
          Ruhezeit aktiv – automatische Benachrichtigungen sind pausiert. Manuell gesendete
          Nachrichten werden trotzdem sofort zugestellt.
        </span>
      </div>

      <.form for={@send_form} id="push-send-form" phx-submit="send" class="mt-6 space-y-4">
        <div class="grid gap-4 sm:grid-cols-2">
          <.input
            field={@send_form[:category]}
            type="select"
            label="Empfänger"
            options={@categories}
          />
          <.input field={@send_form[:title]} label="Titel" required />
        </div>
        <.input field={@send_form[:body]} label="Text" required />
        <.input
          field={@send_form[:url]}
          label="Link (optional)"
          placeholder="Standard: Startseite"
        />
        <.button variant="primary" phx-disable-with="Sende…">Senden</.button>
      </.form>

      <h2 class="mt-10 text-lg font-semibold">
        Abonnements <span class="text-base-content/50">({@sub_count})</span>
      </h2>

      <.table id="subscriptions" rows={@subscriptions}>
        <:col :let={s} label="Dienst">{endpoint_host(s.endpoint)}</:col>
        <:col :let={s} label="Kategorien">
          {if s.categories == [], do: "—", else: Enum.join(s.categories, ", ")}
        </:col>
        <:col :let={s} label="Zuletzt genutzt">
          {if s.last_used, do: Calendar.strftime(s.last_used, "%d.%m.%Y %H:%M"), else: "—"}
        </:col>
        <:col :let={s} label="Fehler">
          <span class={s.error_count > 0 && "text-error font-medium"}>{s.error_count}</span>
          <span :if={s.last_error_at} class="block text-xs text-base-content/50">
            {Calendar.strftime(s.last_error_at, "%d.%m.%Y %H:%M")}
          </span>
        </:col>
        <:action :let={s}>
          <.link
            phx-click={JS.push("delete", value: %{id: s.id})}
            data-confirm="Dieses Abo wirklich löschen?"
            class="link link-error"
            title="Löschen"
            aria-label="Löschen"
          >
            <.icon name="hero-trash" class="size-5" />
          </.link>
        </:action>
      </.table>
    </Layouts.admin>
    """
  end
end
