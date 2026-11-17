defmodule BbhWeb.Admin.MediaBulkEditor do
  @moduledoc """
  Modal for setting metadata on many `Bbh.Media.Upload`s at once — an album of a hundred
  pictures that should all be called "Jugendbiwak 2005" and carry the photographer's
  copyright.

  It is the single-file `BbhWeb.Admin.MediaEditor` minus what only makes sense per
  picture (focal point, rotation). The rule is **only what is changed is written**:

    * Every field opens with the value the selected files share, or empty with the hint
      "Verschiedene Werte" when they differ. Submitting a field unchanged leaves each file
      as it is; editing it overwrites it on all of them.
    * Emptying a shared value clears it everywhere. A field with differing values cannot
      be "emptied" (it already looks empty), so it offers an explicit "Bei allen leeren".
    * The folder select starts on "Unverändert".

  `{n}` in a text field becomes the running number in the media library's current sort
  order (see `Bbh.Media.bulk_update_uploads/3`).

  The host LiveView renders `bulk_editor/1` and handles `"bulk_change"` (keeps the title
  draft for the numbering preview), `"bulk_save"` (hand the params and the common values
  to `changes/2`) and `"cancel_bulk"`.
  """
  use BbhWeb, :html

  alias Bbh.Media

  # Folder select value for "leave the folder alone" — "" already means "no folder".
  @keep_folder "keep"

  @labels %{
    title: "Titel (intern, für die Suche)",
    caption: "Bildunterschrift (öffentlich unter dem Bild)",
    description: "Beschreibung (Alt-Text für Screenreader)",
    copyright: "Copyright"
  }

  @doc """
  Turn a bulk-editor submit into the `changes` map for `Bbh.Media.bulk_update_uploads/3`:
  only the fields whose submitted value differs from what the form showed, plus the
  ones ticked "Bei allen leeren".
  """
  def changes(params, common) when is_map(params) and is_map(common) do
    clear = params |> Map.get("clear", []) |> List.wrap()

    changes =
      for field <- Media.bulk_fields(), reduce: %{} do
        acc ->
          key = Atom.to_string(field)
          shown = common |> Map.get(field) |> shown_value()
          submitted = params |> Map.get(key, "") |> to_string() |> String.trim()

          cond do
            key in clear -> Map.put(acc, field, nil)
            Map.get(common, field) == :mixed and submitted == "" -> acc
            submitted == shown -> acc
            submitted == "" -> Map.put(acc, field, nil)
            true -> Map.put(acc, field, submitted)
          end
      end

    case Map.get(params, "folder_id", @keep_folder) do
      @keep_folder -> changes
      folder_id -> Map.put(changes, :folder_id, folder_id)
    end
  end

  defp shown_value(:mixed), do: ""
  defp shown_value(nil), do: ""
  defp shown_value(value), do: String.trim(value)

  attr :count, :integer, required: true
  attr :common, :map, required: true
  attr :folder_options, :list, required: true
  attr :sort_label, :string, required: true
  attr :title_draft, :string, default: nil

  def bulk_editor(assigns) do
    assigns =
      assign(assigns,
        fields: Media.bulk_fields(),
        counter: Media.counter_placeholder(),
        folder_select: [{"— Unverändert —", @keep_folder} | assigns.folder_options],
        preview: preview(assigns.title_draft, assigns.count)
      )

    ~H"""
    <div class="fixed inset-0 z-50 flex items-end justify-center overflow-y-auto bg-black/40 sm:items-center">
      <div
        id="media-bulk-editor"
        class="w-full max-w-lg rounded-t-box bg-base-100 p-5 shadow-xl sm:rounded-box"
        phx-click-away="cancel_bulk"
        phx-window-keydown="cancel_bulk"
        phx-key="Escape"
      >
        <div class="mb-1 flex items-center justify-between">
          <h3 class="text-lg font-semibold">{@count} Dateien bearbeiten</h3>
          <button
            type="button"
            phx-click="cancel_bulk"
            class="btn btn-ghost btn-sm"
            aria-label="Schließen"
          >
            ✕
          </button>
        </div>
        <p class="mb-4 text-sm text-base-content/70">
          Nur geänderte Felder werden bei allen ausgewählten Dateien überschrieben.
        </p>

        <form id="media-bulk-form" phx-change="bulk_change" phx-submit="bulk_save">
          <div :for={field <- @fields} class="mb-1">
            <.input
              id={"bulk_#{field}"}
              name={"bulk[#{field}]"}
              value={shown_value(@common[field])}
              type={if field == :description, do: "textarea", else: "text"}
              label={label(field)}
              placeholder={@common[field] == :mixed && "Verschiedene Werte – bleiben erhalten"}
            />
            <p :if={field == :title} class="-mt-1 mb-2 text-xs text-base-content/60">
              <code class="rounded bg-base-200 px-1">{@counter}</code>
              wird zur laufenden Nummer in der aktuellen Sortierung ({@sort_label}).
            </p>
            <p
              :if={field == :title and @preview}
              id="bulk-title-preview"
              class="-mt-1 mb-2 text-xs text-base-content/80"
            >
              Vorschau: „{elem(@preview, 0)}“ … „{elem(@preview, 1)}“
            </p>
            <label
              :if={@common[field] == :mixed}
              class="-mt-1 mb-2 flex cursor-pointer items-center gap-2 text-xs text-base-content/70"
            >
              <input
                type="checkbox"
                id={"bulk_clear_#{field}"}
                name="bulk[clear][]"
                value={field}
                class="checkbox checkbox-xs"
              /> Bei allen leeren
            </label>
          </div>
          <.input
            id="bulk_folder_id"
            name="bulk[folder_id]"
            value={keep_folder()}
            type="select"
            label="Ordner"
            options={@folder_select}
          />
          <div class="mt-3 flex gap-2">
            <.button variant="primary" phx-disable-with="Speichern…">
              Bei {@count} Dateien speichern
            </.button>
            <button type="button" phx-click="cancel_bulk" class="btn btn-ghost">Abbrechen</button>
          </div>
        </form>
      </div>
    </div>
    """
  end

  defp label(field), do: Map.fetch!(@labels, field)

  defp keep_folder, do: @keep_folder

  # First and last title, so "Biwak ({n})" visibly becomes "Biwak (1)" … "Biwak (100)".
  defp preview(draft, count) when is_binary(draft) and count > 0 do
    counter = Media.counter_placeholder()

    if String.contains?(draft, counter) do
      draft = String.trim(draft)
      {String.replace(draft, counter, "1"), String.replace(draft, counter, to_string(count))}
    end
  end

  defp preview(_draft, _count), do: nil
end
