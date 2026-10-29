defmodule BbhWeb.Admin.RedirectLive.Index do
  @moduledoc """
  Admin-only: editor-managed redirects, a path checker, and the 404 log with one-click
  „Weiterleitung anlegen“. See `Bbh.Redirects` for how requests are resolved.
  """
  use BbhWeb, :live_view

  alias Bbh.Redirects
  alias BbhWeb.AdminList

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign(:page_title, "Weiterleitungen")
     |> assign(:list_state, AdminList.init(sort: "source", dir: :asc))
     |> assign(:check_form, to_form(%{"path" => ""}, as: "check"))
     |> assign(:check_result, nil)
     |> load_list()
     |> load_not_found()}
  end

  @impl true
  def handle_event("list-" <> action, params, socket),
    do: {:noreply, AdminList.handle(action, params, socket, &load_list/1)}

  def handle_event("check", %{"check" => %{"path" => path}}, socket) do
    result = if String.trim(path) == "", do: nil, else: check(path)

    {:noreply,
     assign(socket, check_form: to_form(%{"path" => path}, as: "check"), check_result: result)}
  end

  def handle_event("dismiss", %{"id" => id}, socket) do
    Redirects.delete_not_found(id)
    {:noreply, load_not_found(socket)}
  end

  defp check(path) do
    normalized = Redirects.normalize_path(path)

    case Redirects.resolve(normalized) do
      {:rule, rule} ->
        {:rule, normalized, rule.target, if(rule.permanent, do: 301, else: 302)}

      {:legacy, target} ->
        {:legacy, normalized, target}

      nil ->
        {:none, normalized}
    end
  end

  defp load_list(socket) do
    meta =
      AdminList.process(Redirects.list_redirects(), socket.assigns.list_state,
        search: [& &1.source_path, & &1.target, & &1.note],
        sort: %{
          "source" => & &1.source_path,
          "hits" => & &1.hits,
          "last_hit" => & &1.last_hit_at
        }
      )

    assign(socket, redirects: meta.entries, list_meta: meta)
  end

  defp load_not_found(socket) do
    entries = Redirects.list_not_found()
    assign(socket, not_found: entries, not_found_count: length(entries))
  end

  defp local_time(nil), do: "—"

  defp local_time(%DateTime{} = dt) do
    dt =
      case DateTime.shift_zone(dt, Bbh.Time.time_zone()) do
        {:ok, local} -> local
        _ -> dt
      end

    Calendar.strftime(dt, "%d.%m.%Y %H:%M")
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.admin flash={@flash} current_scope={@current_scope} active={:redirects}>
      <.header>
        Weiterleitungen
        <:subtitle>
          Greifen nur, wenn unter der Adresse keine Seite existiert. Alte Adressen der
          früheren Website werden zusätzlich automatisch weitergeleitet.
        </:subtitle>
        <:actions>
          <.button variant="primary" navigate={~p"/admin/weiterleitungen/neu"}>
            Neue Weiterleitung
          </.button>
        </:actions>
      </.header>

      <section class="rounded-box border border-base-300 p-4">
        <h2 class="text-sm font-semibold">Adresse prüfen</h2>
        <.form
          for={@check_form}
          id="check-form"
          phx-submit="check"
          class="mt-2 flex flex-wrap items-end gap-2"
        >
          <div class="min-w-64 grow">
            <.input field={@check_form[:path]} placeholder="/aktuell/2020/kein_biwak" />
          </div>
          <.button phx-disable-with="Prüfe…" class="btn btn-primary btn-soft mb-2">Prüfen</.button>
        </.form>

        <p :if={@check_result} id="check-result" class="mt-2 text-sm">
          <%= case @check_result do %>
            <% {:rule, path, target, status} -> %>
              <span class="font-mono">{path}</span> → <span class="font-mono">{target}</span>
              <span class="badge badge-sm ml-1">{status}, Weiterleitung</span>
            <% {:legacy, path, target} -> %>
              <span class="font-mono">{path}</span> → <span class="font-mono">{target}</span>
              <span class="badge badge-sm ml-1">301, alte Adresse (automatisch)</span>
            <% {:none, path} -> %>
              <span class="font-mono">{path}</span>: keine Weiterleitung – ohne Seite
              unter dieser Adresse gibt es „nicht gefunden“.
          <% end %>
        </p>
      </section>

      <h2 class="mt-8 mb-2 text-lg font-semibold">Regeln</h2>

      <.list_search q={@list_meta.q} placeholder="Nach Adresse suchen…" />

      <.table
        id="redirects"
        rows={@redirects}
        row_id={&"redirect-#{&1.id}"}
        sort={@list_meta.sort}
        dir={@list_meta.dir}
      >
        <:col :let={r} label="Von" sort_key="source">
          <span class="font-mono text-sm">{r.source_path}</span>
          <span :if={r.note} class="block text-xs text-base-content/60">{r.note}</span>
        </:col>
        <:col :let={r} label="Nach">
          <span class="font-mono text-sm break-all">{r.target}</span>
        </:col>
        <:col :let={r} label="Art">{if r.permanent, do: "301", else: "302"}</:col>
        <:col :let={r} label="Aufrufe" sort_key="hits">{r.hits}</:col>
        <:col :let={r} label="Zuletzt" sort_key="last_hit">{local_time(r.last_hit_at)}</:col>
        <:action :let={r}>
          <.link
            navigate={~p"/admin/weiterleitungen/#{r.id}/bearbeiten"}
            class="link link-primary"
            title="Bearbeiten"
            aria-label="Bearbeiten"
          >
            <.icon name="hero-pencil-square" class="size-5" />
          </.link>
        </:action>
      </.table>

      <.list_pagination meta={@list_meta} />

      <h2 class="mt-10 text-lg font-semibold">
        Nicht gefunden <span class="text-base-content/50">({@not_found_count})</span>
      </h2>
      <p class="mb-2 text-sm text-base-content/70">
        Adressen, die zuletzt ins Leere liefen – meist alte Links von anderen Seiten oder
        aus Suchmaschinen. Einträge ohne Aufruf seit 90 Tagen verschwinden automatisch.
      </p>

      <.table id="not-found" rows={@not_found} row_id={&"not-found-#{&1.id}"}>
        <:col :let={n} label="Adresse">
          <span class="font-mono text-sm break-all">{n.path}</span>
          <span :if={n.referrer} class="block text-xs text-base-content/60 break-all">
            von {n.referrer}
          </span>
        </:col>
        <:col :let={n} label="Aufrufe">{n.hits}</:col>
        <:col :let={n} label="Zuletzt">{local_time(n.last_seen_at)}</:col>
        <:action :let={n}>
          <.link
            navigate={~p"/admin/weiterleitungen/neu?#{[von: n.path]}"}
            class="link link-primary"
            title="Weiterleitung anlegen"
            aria-label="Weiterleitung anlegen"
          >
            <.icon name="hero-arrow-uturn-right" class="size-5" />
          </.link>
          <.link
            id={"dismiss-#{n.id}"}
            phx-click={JS.push("dismiss", value: %{id: n.id})}
            class="link link-hover text-base-content/60"
            title="Ignorieren"
            aria-label="Ignorieren"
          >
            <.icon name="hero-eye-slash" class="size-5" />
          </.link>
        </:action>
      </.table>
    </Layouts.admin>
    """
  end
end
