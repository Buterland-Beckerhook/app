defmodule BbhWeb.Admin.BlzLive do
  @moduledoc """
  Admin-only refresh of the BLZ table (`Bbh.Blz`) behind the membership form's
  IBAN → BIC/Kreditinstitut derivation: upload the Bundesbank CSV, review what it
  changes against the active table, then apply it — or drop the upload and fall back
  to the copy shipped in the release.
  """
  use BbhWeb, :live_view

  alias Bbh.Blz

  # Rows shown per diff section; the counts above them are always complete.
  @shown 100

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign(page_title: "Bankleitzahlen", preview: nil, shown: @shown)
     |> assign_status()
     |> allow_upload(:csv,
       accept: ~w(.csv),
       max_entries: 1,
       max_file_size: 10_000_000,
       auto_upload: true,
       progress: &handle_progress/3
     )}
  end

  # The preview is built as soon as the file is up — there is nothing to fill in first.
  # `path` is LiveView's server-side temp file for the entry, not client input.
  # sobelow_skip ["Traversal.FileModule"]
  defp handle_progress(:csv, entry, socket) do
    if entry.done? do
      result =
        consume_uploaded_entry(socket, entry, fn %{path: path} ->
          {:ok, path |> File.read!() |> Blz.parse_bundesbank()}
        end)

      case result do
        {:ok, table} ->
          preview = %{file: entry.client_name, table: table, diff: Blz.diff(table)}
          {:noreply, assign(socket, preview: preview)}

        {:error, :too_few_entries} ->
          {:noreply,
           socket
           |> assign(preview: nil)
           |> put_flash(
             :error,
             "Die Datei sieht nicht nach der Bankleitzahlendatei der Bundesbank aus."
           )}
      end
    else
      {:noreply, socket}
    end
  end

  @impl true
  def handle_event("validate", _params, socket), do: {:noreply, socket}

  def handle_event("apply", _params, %{assigns: %{preview: %{table: table}}} = socket) do
    case Blz.import(table) do
      :ok ->
        {:noreply,
         socket
         |> assign(preview: nil)
         |> assign_status()
         |> put_flash(:info, "#{map_size(table)} Bankleitzahlen übernommen.")}

      {:error, reason} ->
        {:noreply, put_flash(socket, :error, "Speichern fehlgeschlagen (#{inspect(reason)}).")}
    end
  end

  def handle_event("apply", _params, socket), do: {:noreply, socket}

  def handle_event("discard", _params, socket), do: {:noreply, assign(socket, preview: nil)}

  def handle_event("reset", _params, socket) do
    case Blz.reset() do
      :ok ->
        {:noreply,
         socket
         |> assign(preview: nil)
         |> assign_status()
         |> put_flash(:info, "Upload entfernt – die mitgelieferte Tabelle ist wieder aktiv.")}

      {:error, reason} ->
        {:noreply, put_flash(socket, :error, "Entfernen fehlgeschlagen (#{inspect(reason)}).")}
    end
  end

  defp assign_status(socket), do: assign(socket, status: Blz.status())

  defp unchanged?(%{added: [], removed: [], changed: []}), do: true
  defp unchanged?(_diff), do: false

  defp local(dt), do: DateTime.shift_zone!(dt, Bbh.Time.time_zone())

  defp upload_error_label(:too_large), do: "Datei ist zu groß (max. 10 MB)."
  defp upload_error_label(:not_accepted), do: "Bitte die CSV-Datei hochladen (nicht die ZIP)."
  defp upload_error_label(:too_many_files), do: "Bitte nur eine Datei."
  defp upload_error_label(_), do: "Fehler beim Hochladen."

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.admin flash={@flash} current_scope={@current_scope} active={:blz}>
      <.header>
        Bankleitzahlen
        <:subtitle>
          Aus der IBAN ergänzt das Mitgliedsformular BIC und Kreditinstitut. Die Bundesbank
          veröffentlicht die Bankleitzahlendatei vierteljährlich neu.
        </:subtitle>
      </.header>

      <div id="blz-status" class="mt-6 rounded-box border border-base-300 p-4">
        <p :if={@status.source == :upload}>
          Aktiv: <strong>hochgeladene Tabelle</strong>
          vom {de_datetime(local(@status.uploaded_at))} · {@status.entries} Einträge
        </p>
        <p :if={@status.source == :shipped}>
          Aktiv: <strong>mitgelieferte Tabelle</strong> · {@status.entries} Einträge
        </p>
        <p :if={@status.source == :none} class="text-warning">
          Keine Tabelle geladen – BIC und Kreditinstitut werden nicht ergänzt.
        </p>
        <button
          :if={@status.source == :upload}
          type="button"
          id="blz-reset"
          phx-click="reset"
          data-confirm="Upload entfernen und zur mitgelieferten Tabelle zurückkehren?"
          class="btn btn-ghost btn-sm mt-2"
        >
          Upload entfernen
        </button>
      </div>

      <ol class="mt-6 list-decimal space-y-1 pl-5 text-sm">
        <li>
          <.link href={Blz.download_page()} target="_blank" rel="noopener" class="link">
            Download-Seite der Bundesbank
          </.link>
          öffnen und die Bankleitzahlendatei als <strong>CSV</strong>
          (nicht gepackt) herunterladen.
        </li>
        <li>Die Datei hier hochladen – die Änderungen erscheinen als Vorschau.</li>
        <li>Vorschau prüfen und übernehmen.</li>
      </ol>

      <form id="blz-upload-form" phx-change="validate" phx-submit="validate" class="mt-4">
        <div
          class="rounded-box border-2 border-dashed border-base-300 p-6 text-center"
          phx-drop-target={@uploads.csv.ref}
        >
          <.live_file_input upload={@uploads.csv} class="file-input file-input-bordered" />
          <p class="mt-2 text-sm text-base-content/60">blz-aktuell-csv-data.csv · bis 10&nbsp;MB</p>
        </div>
        <div :for={entry <- @uploads.csv.entries} class="mt-2">
          <progress class="progress progress-primary w-full" value={entry.progress} max="100" />
          <p :for={err <- upload_errors(@uploads.csv, entry)} class="text-sm text-error">
            {upload_error_label(err)}
          </p>
        </div>
        <p :for={err <- upload_errors(@uploads.csv)} class="text-sm text-error">
          {upload_error_label(err)}
        </p>
      </form>

      <section :if={@preview} id="blz-preview" class="mt-8 space-y-6">
        <h2 class="text-lg font-semibold">Vorschau: {@preview.file}</h2>
        <p>
          {map_size(@preview.table)} Einträge ·
          <span class="text-success">{length(@preview.diff.added)} neu</span>
          · <span class="text-warning">{length(@preview.diff.changed)} geändert</span>
          · <span class="text-error">{length(@preview.diff.removed)} entfallen</span>
        </p>

        <p :if={unchanged?(@preview.diff)} class="alert">
          Keine Änderungen gegenüber der aktiven Tabelle.
        </p>

        <.diff_section
          :if={@preview.diff.changed != []}
          id="blz-changed"
          title="Geändert"
          rows={@preview.diff.changed}
          shown={@shown}
        >
          <:row :let={{blz, {old_bic, old_name}, {new_bic, new_name}}}>
            <td class="font-mono">{blz}</td>
            <td class="font-mono">
              <span :if={old_bic != new_bic}>
                <del class="text-error">{old_bic}</del> → <ins class="text-success">{new_bic}</ins>
              </span>
              <span :if={old_bic == new_bic}>{new_bic}</span>
            </td>
            <td>
              <span :if={old_name != new_name}>
                <del class="text-error">{old_name}</del> → <ins class="text-success">{new_name}</ins>
              </span>
              <span :if={old_name == new_name}>{new_name}</span>
            </td>
          </:row>
        </.diff_section>

        <.diff_section
          :if={@preview.diff.added != []}
          id="blz-added"
          title="Neu"
          rows={@preview.diff.added}
          shown={@shown}
        >
          <:row :let={{blz, bic, name}}>
            <td class="font-mono">{blz}</td>
            <td class="font-mono">{bic}</td>
            <td>{name}</td>
          </:row>
        </.diff_section>

        <.diff_section
          :if={@preview.diff.removed != []}
          id="blz-removed"
          title="Entfallen"
          rows={@preview.diff.removed}
          shown={@shown}
        >
          <:row :let={{blz, bic, name}}>
            <td class="font-mono">{blz}</td>
            <td class="font-mono">{bic}</td>
            <td>{name}</td>
          </:row>
        </.diff_section>

        <div class="flex gap-2">
          <.button
            id="blz-apply"
            variant="primary"
            phx-click="apply"
            phx-disable-with="Übernehme…"
            disabled={unchanged?(@preview.diff)}
          >
            Übernehmen
          </.button>
          <.button id="blz-discard" phx-click="discard">Verwerfen</.button>
        </div>
      </section>
    </Layouts.admin>
    """
  end

  attr :id, :string, required: true
  attr :title, :string, required: true
  attr :rows, :list, required: true
  attr :shown, :integer, required: true
  slot :row, required: true

  defp diff_section(assigns) do
    ~H"""
    <details id={@id} open={length(@rows) <= 20}>
      <summary class="cursor-pointer font-medium">{@title} ({length(@rows)})</summary>
      <div class="mt-2 overflow-x-auto">
        <table class="table table-sm">
          <thead>
            <tr>
              <th>BLZ</th>
              <th>BIC</th>
              <th>Kreditinstitut</th>
            </tr>
          </thead>
          <tbody>
            <tr :for={row <- Enum.take(@rows, @shown)}>{render_slot(@row, row)}</tr>
          </tbody>
        </table>
        <p :if={length(@rows) > @shown} class="mt-1 text-sm text-base-content/60">
          … und {length(@rows) - @shown} weitere
        </p>
      </div>
    </details>
    """
  end
end
