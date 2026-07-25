defmodule BbhWeb.Admin.MediaEditor do
  @moduledoc """
  Shared modal for editing a single `Bbh.Media.Upload`'s metadata and crop focal
  point. Used by the media library and the article form, so the focal point can be
  set without a detour to `/admin/medien`.

  The host LiveView must handle the `"save_meta"` (form submit, params under
  `"upload"`) and `"cancel_edit"` events, and provide `folder_options` (see
  `Bbh.Media.folder_options/0`).
  """
  use BbhWeb, :html

  alias Bbh.Media

  attr :upload, :map, required: true
  attr :folder_options, :list, required: true

  def media_editor(assigns) do
    ~H"""
    <div class="fixed inset-0 z-50 flex items-end justify-center bg-black/40 sm:items-center">
      <div
        class="w-full max-w-lg rounded-t-box bg-base-100 p-5 shadow-xl sm:rounded-box"
        phx-click-away="cancel_edit"
      >
        <div class="mb-3 flex items-center justify-between">
          <h3 class="text-lg font-semibold">Datei bearbeiten</h3>
          <button
            type="button"
            phx-click="cancel_edit"
            class="btn btn-ghost btn-sm"
            aria-label="Schließen"
          >
            ✕
          </button>
        </div>

        <div class="mb-3 flex items-center gap-3">
          <span
            :if={not Media.image?(@upload)}
            class="flex size-16 items-center justify-center rounded bg-base-200"
          >
            <.icon name="hero-document-text" class="size-8 text-base-content/60" />
          </span>
          <span class="truncate text-sm text-base-content/70">{@upload.filename}</span>
        </div>

        <.form
          for={to_form(Media.change_upload(@upload), as: "upload")}
          id="media-edit-form"
          phx-submit="save_meta"
        >
          <div :if={Media.image?(@upload)} class="mb-4">
            <div class="mb-1 flex items-center justify-between">
              <span class="text-sm font-medium">Mittelpunkt für Zuschnitte</span>
              <button type="button" data-focal-reset class="btn btn-ghost btn-xs">
                Zentrieren
              </button>
            </div>
            <div
              id="focal-picker"
              phx-hook="FocalPoint"
              data-x-input="upload_focal_point_x"
              data-y-input="upload_focal_point_y"
              class="relative inline-block max-w-full cursor-crosshair overflow-hidden rounded border border-base-300 bg-base-200"
            >
              <img
                src={media_url(@upload, width: 400)}
                alt=""
                draggable="false"
                class="block max-h-64 w-auto max-w-full select-none"
              />
              <div
                data-focal-marker
                class="pointer-events-none absolute size-6 -translate-x-1/2 -translate-y-1/2 rounded-full border-2 border-white shadow ring-2 ring-black/40"
                style={"left: #{focal_pct(@upload.focal_point_x)}%; top: #{focal_pct(@upload.focal_point_y)}%"}
              >
              </div>
            </div>
            <p class="mt-1 text-xs text-base-content/60">
              Ins Bild klicken, um festzulegen, worauf beschnittene Vorschaubilder zentriert werden.
            </p>
          </div>
          <input
            type="hidden"
            name="upload[focal_point_x]"
            id="upload_focal_point_x"
            value={@upload.focal_point_x}
          />
          <input
            type="hidden"
            name="upload[focal_point_y]"
            id="upload_focal_point_y"
            value={@upload.focal_point_y}
          />
          <.input name="upload[title]" value={@upload.title} label="Titel" />
          <.input
            name="upload[description]"
            value={@upload.description}
            label="Beschreibung"
            type="textarea"
          />
          <.input name="upload[copyright]" value={@upload.copyright} label="Copyright" />
          <.input
            name="upload[folder_id]"
            value={@upload.folder_id || ""}
            type="select"
            label="Ordner"
            options={@folder_options}
          />
          <div class="mt-3 flex gap-2">
            <.button variant="primary" phx-disable-with="Speichern…">Speichern</.button>
            <button type="button" phx-click="cancel_edit" class="btn btn-ghost">Abbrechen</button>
          </div>
        </.form>
      </div>
    </div>
    """
  end

  # Marker position (percent) for the focal picker; nil focal defaults to center.
  defp focal_pct(nil), do: 50
  defp focal_pct(v) when is_number(v), do: Float.round(v * 100.0, 2)
end
