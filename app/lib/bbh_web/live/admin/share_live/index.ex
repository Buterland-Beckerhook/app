defmodule BbhWeb.Admin.ShareLive.Index do
  use BbhWeb, :live_view

  alias Bbh.Calendar
  alias Bbh.Calendar.CalendarShare
  alias BbhWeb.Authz

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign(:page_title, "Kalender teilen")
     |> assign(:new_share, nil)
     |> assign_form()
     |> load_shares()}
  end

  @impl true
  def handle_event("create", %{"share" => params}, socket) do
    user = socket.assigns.current_scope.user
    calendar = params["calendar"]

    if Authz.can_manage_calendar?(user, calendar) do
      attrs = %{
        recipient_label: blank_to_nil(params["recipient_label"]),
        expires_at: parse_date(params["expires_at"])
      }

      case Calendar.create_share(calendar, attrs, user) do
        {:ok, {plaintext, share}} ->
          url = url(~p"/kalender/geteilt/#{plaintext}")
          {level, message} = create_flash(share, url, params["notify"])

          {:noreply,
           socket
           |> assign(:new_share, %{share: share, url: url, qr: qr_svg(url)})
           |> put_flash(level, message)
           |> assign_form()
           |> load_shares()}

        {:error, changeset} ->
          {:noreply, assign(socket, :form, to_form(changeset, as: "share"))}
      end
    else
      {:noreply, put_flash(socket, :error, "Für diesen Kalender fehlt die Berechtigung.")}
    end
  end

  def handle_event("revoke", %{"id" => id}, socket) do
    user = socket.assigns.current_scope.user
    share = Enum.find(socket.assigns.shares, &(&1.id == id))

    cond do
      is_nil(share) ->
        {:noreply, socket}

      not Authz.can_manage_calendar?(user, share.calendar) ->
        {:noreply, put_flash(socket, :error, "Für diesen Kalender fehlt die Berechtigung.")}

      true ->
        {:ok, _} = Calendar.revoke_share(id)

        {:noreply,
         socket
         |> put_flash(:info, "Link widerrufen.")
         |> maybe_clear_new_share(id)
         |> load_shares()}
    end
  end

  def handle_event("resend", %{"id" => id}, socket) do
    user = socket.assigns.current_scope.user
    share = Enum.find(socket.assigns.shares, &(&1.id == id))

    cond do
      is_nil(share) ->
        {:noreply, socket}

      not Authz.can_manage_calendar?(user, share.calendar) ->
        {:noreply, put_flash(socket, :error, "Für diesen Kalender fehlt die Berechtigung.")}

      # Recompute activity freshly: the rendered button uses a possibly-stale @now,
      # and the share may have been revoked/expired since the page loaded. Rotating
      # an inactive share would mint a link that verify_share_token still rejects.
      not CalendarShare.active?(share) ->
        {:noreply,
         socket
         |> put_flash(:error, "Dieser Link ist nicht mehr aktiv und kann nicht erneuert werden.")
         |> load_shares()}

      true ->
        case Calendar.rotate_share_token(share) do
          {:ok, {plaintext, share}} ->
            url = url(~p"/kalender/geteilt/#{plaintext}")
            {level, message} = resend_flash(share, url)

            {:noreply,
             socket
             |> assign(:new_share, %{share: share, url: url, qr: qr_svg(url)})
             |> put_flash(level, message)
             |> load_shares()}

          {:error, _changeset} ->
            {:noreply, put_flash(socket, :error, "Der Link konnte nicht erneuert werden.")}
        end
    end
  end

  # Resend rotates the token; on success the previously-issued link stops working.
  defp resend_flash(share, url) do
    case Calendar.deliver_share_link(share, url) do
      {:ok, _} ->
        {:info,
         "Neuer Link per E-Mail an #{share.recipient_label} gesendet. Der bisherige Link ist ungültig."}

      {:error, _} ->
        {:error,
         "Neuer Link erstellt, aber der E-Mail-Versand ist fehlgeschlagen. Bitte den Link manuell kopieren."}

      :skip ->
        {:info,
         "Neuer Link erstellt. Der bisherige Link ist ungültig — bitte den neuen kopieren."}
    end
  end

  # A freshly-minted token is only shown once. When the admin asked to email it,
  # the flash must reflect what actually happened with delivery — not just the
  # recipient-label heuristic.
  defp create_flash(share, url, "true") do
    case Calendar.deliver_share_link(share, url) do
      {:ok, _} ->
        {:info, "Link erstellt und per E-Mail an #{share.recipient_label} gesendet."}

      {:error, _} ->
        {:error,
         "Link erstellt, aber der E-Mail-Versand ist fehlgeschlagen. Bitte den Link manuell kopieren."}

      :skip ->
        {:info, base_notice()}
    end
  end

  defp create_flash(_share, _url, _notify), do: {:info, base_notice()}

  defp base_notice, do: "Link erstellt. Der Link ist nur jetzt sichtbar — bitte kopieren."

  defp maybe_clear_new_share(socket, id) do
    case socket.assigns.new_share do
      %{share: %{id: ^id}} -> assign(socket, :new_share, nil)
      _ -> socket
    end
  end

  defp assign_form(socket) do
    default = socket |> shareable_options() |> List.first() |> elem_value()

    form =
      to_form(
        %{
          "calendar" => default,
          "recipient_label" => "",
          "expires_at" => "",
          "notify" => "false"
        },
        as: "share"
      )

    assign(socket, :form, form)
  end

  defp elem_value(nil), do: nil
  defp elem_value({_label, value}), do: value

  defp load_shares(socket) do
    calendars = socket |> shareable_options() |> Enum.map(&elem(&1, 1))

    socket
    |> assign(:shares, Calendar.list_shares(calendars))
    |> assign(:calendar_options, shareable_options(socket))
    |> assign(:now, Bbh.Time.now())
  end

  # Calendars the user may share — the assignable named calendars, minus the
  # public ("Öffentlich") pseudo-option (public events are already public).
  defp shareable_options(socket) do
    socket.assigns.current_scope.user
    |> Authz.assignable_calendar_options()
    |> Enum.reject(fn {_label, value} -> value == "" end)
  end

  defp qr_svg(url), do: url |> EQRCode.encode() |> EQRCode.svg(width: 180)

  defp blank_to_nil(v) when v in [nil, ""], do: nil
  defp blank_to_nil(v), do: v

  # Native date input → end-of-day so the link stays valid *through* that date;
  # blank → nil (no expiry).
  defp parse_date(v) when v in [nil, ""], do: nil
  defp parse_date(v) when is_binary(v), do: v <> "T23:59:59Z"

  defp status(share, now) do
    cond do
      CalendarShare.revoked?(share) -> {"Widerrufen", "badge-error"}
      CalendarShare.expired?(share, now) -> {"Abgelaufen", "badge-warning"}
      true -> {"Aktiv", "badge-success"}
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.admin flash={@flash} current_scope={@current_scope} active={:shares}>
      <.header>
        Kalender teilen
        <:subtitle>
          Erzeuge widerrufbare Abo-Links für einen internen Kalender — pro Empfänger einer.
        </:subtitle>
        <:actions>
          <.button navigate={~p"/admin/termine"}>Zu den Terminen</.button>
        </:actions>
      </.header>

      <div :if={@calendar_options == []} class="mt-6 alert alert-info">
        Dir ist derzeit kein interner Kalender zum Teilen zugewiesen.
      </div>

      <.form
        :if={@calendar_options != []}
        for={@form}
        id="share-form"
        phx-submit="create"
        class="mt-6 space-y-4 max-w-xl"
      >
        <.input
          field={@form[:calendar]}
          type="select"
          label="Kalender"
          options={@calendar_options}
        />
        <.input
          field={@form[:recipient_label]}
          label="Empfänger (E-Mail oder Bezeichnung)"
          placeholder="z. B. kassierer@example.com"
        />
        <.input field={@form[:expires_at]} type="date" label="Ablauf (optional, leer = unbegrenzt)" />
        <.input
          field={@form[:notify]}
          type="checkbox"
          label="Link per E-Mail an den Empfänger senden (nur bei E-Mail-Adresse)"
        />
        <.button variant="primary" phx-disable-with="Erstelle…">Link erstellen</.button>
      </.form>

      <div
        :if={@new_share}
        id="new-share"
        class="mt-6 rounded-box border border-success/40 bg-success/5 p-4"
      >
        <p class="mb-2 font-medium">
          Neuer Link für „{Bbh.Calendar.Event.calendar_label(@new_share.share.calendar)}"
        </p>
        <p class="mb-3 text-sm text-base-content/70">
          Dieser Link wird nur jetzt angezeigt. Kopiere ihn oder scanne den QR-Code.
        </p>
        <div class="flex flex-col gap-4 sm:flex-row sm:items-start">
          <input
            type="text"
            readonly
            value={@new_share.url}
            class="input input-bordered w-full font-mono text-sm"
            aria-label="Geteilter Link"
          />
          <div class="shrink-0 bg-white p-3 rounded-box">{Phoenix.HTML.raw(@new_share.qr)}</div>
        </div>
      </div>

      <h2 class="mt-10 mb-3 text-lg font-semibold">Bestehende Links</h2>
      <.table id="shares" rows={@shares}>
        <:col :let={s} label="Kalender">{Bbh.Calendar.Event.calendar_label(s.calendar)}</:col>
        <:col :let={s} label="Empfänger">{s.recipient_label}</:col>
        <:col :let={s} label="Status">
          <% {text, cls} = status(s, @now) %>
          <span class={["badge badge-sm", cls]}>{text}</span>
        </:col>
        <:col :let={s} label="Ablauf">{s.expires_at && de_date(s.expires_at)}</:col>
        <:col :let={s} label="Zuletzt genutzt">{s.last_used_at && de_datetime(s.last_used_at)}</:col>
        <:action :let={s}>
          <div :if={CalendarShare.active?(s, @now)} class="flex justify-end gap-2">
            <.button
              id={"resend-#{s.id}"}
              phx-click="resend"
              phx-value-id={s.id}
              data-confirm="Neuen Link erzeugen? Der bisherige Link wird sofort ungültig."
            >
              {if CalendarShare.emailable?(s), do: "Neu senden", else: "Neuer Link"}
            </.button>
            <.button
              id={"revoke-#{s.id}"}
              phx-click="revoke"
              phx-value-id={s.id}
              data-confirm="Diesen Link dauerhaft widerrufen?"
            >
              Widerrufen
            </.button>
          </div>
        </:action>
      </.table>
    </Layouts.admin>
    """
  end
end
