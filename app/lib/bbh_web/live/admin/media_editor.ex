defmodule BbhWeb.Admin.MediaEditor do
  @moduledoc """
  Shared modal for editing a single `Bbh.Media.Upload`: its metadata (Titel,
  Bildunterschrift, Beschreibung/Alt-Text, Copyright, Ordner), the crop focal point,
  and quarter-turn rotation.

  This is the **only** place image metadata is edited. An embedding — an article image,
  a gallery file — decides how a picture is used, never what it says; so the same
  picture reads the same everywhere it appears.

  The host LiveView renders `media_editor/1`, keeps the edited upload in an assign, and
  handles two events:

    * `"save_meta"` — the form submit. Params carry the metadata under `"upload"` plus,
      when the submit came from a rotate button, a top-level `"rotate"` angle. Hand the
      whole param map to `submit/2` and act on the returned instruction.
    * `"cancel_edit"` — drop the assign.

  Rotation is wired as a *submit* rather than its own event on purpose: it round-trips
  through the same form, so metadata typed but not yet saved survives the turn.
  """
  use BbhWeb, :html

  alias Bbh.Media
  alias Bbh.Media.Upload

  @doc """
  Apply a media-editor submit: save the metadata and, when the submit came from a rotate
  button, turn the original too.

  Returns `{action, upload, {flash_kind, message}}` — the host assigns `upload` back (so
  the modal never shows values that are already saved), flashes the message, and drops
  the modal unless `action` is `:keep`:

    * `{:close, saved, {:info, _}}` — plain save
    * `{:keep, rotated, {:info, _}}` — rotated; stay in the editor so the turn is visible
      and can be repeated
    * `{:keep, upload, {:error, _}}` — something went wrong; stay open on the upload as it
      now stands. A failed rotation still leaves the metadata saved and, because the new
      bytes are only moved into place on success, the original file untouched.
  """
  def submit(%Upload{} = upload, %{"upload" => attrs} = params) do
    case Media.update_upload(upload, attrs) do
      {:ok, saved} ->
        maybe_rotate(saved, params["rotate"])

      {:error, %Ecto.Changeset{}} ->
        {:keep, upload, {:error, "Bild konnte nicht gespeichert werden."}}
    end
  end

  defp maybe_rotate(upload, nil), do: {:close, upload, {:info, "Bild gespeichert."}}

  defp maybe_rotate(upload, degrees) do
    case Integer.parse(to_string(degrees)) do
      {degrees, ""} -> rotate(upload, degrees)
      _ -> {:keep, upload, {:error, "Ungültiger Drehwinkel."}}
    end
  end

  defp rotate(upload, degrees) do
    case Media.rotate_upload(upload, degrees) do
      {:ok, rotated} ->
        {:keep, rotated, {:info, "Bild gedreht."}}

      {:error, :not_rotatable} ->
        {:keep, upload, {:error, "Dieser Dateityp kann nicht gedreht werden."}}

      {:error, :invalid_angle} ->
        {:keep, upload, {:error, "Ungültiger Drehwinkel."}}

      {:error, _reason} ->
        {:keep, upload, {:error, "Bild konnte nicht gedreht werden."}}
    end
  end

  attr :upload, :map, required: true
  attr :folder_options, :list, required: true

  def media_editor(assigns) do
    ~H"""
    <div class="fixed inset-0 z-50 flex items-end justify-center overflow-y-auto bg-black/40 sm:items-center">
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
          <%!-- Enter in a text field triggers the form's *first* submit button. The
                rotate buttons below are submits (that is how a turn keeps unsaved text),
                so without this hidden one first, Enter would rotate the image instead of
                saving it. --%>
          <button type="submit" class="hidden" tabindex="-1" aria-hidden="true">Speichern</button>

          <div :if={Media.rotatable?(@upload)} class="mb-4">
            <span class="label mb-1">Drehen</span>
            <div class="flex flex-wrap items-center gap-2">
              <button
                :for={{degrees, icon, label} <- rotation_buttons()}
                type="submit"
                name="rotate"
                value={degrees}
                class="btn btn-outline btn-sm gap-1"
                phx-disable-with="Dreht…"
              >
                <.icon name={icon} class="size-4" />{label}
              </button>
            </div>
            <p class="mt-1 text-xs text-base-content/60">
              Drehen speichert die Angaben unten mit.
            </p>
          </div>

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
          <.input name="upload[title]" value={@upload.title} label="Titel (intern, für die Suche)" />
          <.input
            name="upload[caption]"
            value={@upload.caption}
            label="Bildunterschrift (öffentlich unter dem Bild)"
          />
          <%!-- BbhWeb.Format.image_alt/1 already falls back description → caption →
                title, so an empty alt text is a decision, not a gap. Nothing in the form
                used to say so. The fallback *value* is read from alt_fallback/1 rather
                than restated here, so the title case — the internal library label going
                out as public alt text — is visible rather than surprising. --%>
          <.input
            name="upload[description]"
            value={@upload.description}
            placeholder={alt_fallback(@upload)}
            label="Beschreibung (Alt-Text für Screenreader)"
            type="textarea"
          />
          <p :if={alt_fallback(@upload)} class="-mt-1 mb-2 text-xs text-base-content/60">
            Leer lassen: „{alt_fallback(@upload)}“ wird als Alt-Text benutzt.
          </p>
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

  # 180° is deliberately not offered: two clicks get there, and a third button crowds
  # the row for a case that barely comes up.
  defp rotation_buttons do
    [
      {270, "hero-arrow-uturn-left", "Links"},
      {90, "hero-arrow-uturn-right", "Rechts"}
    ]
  end

  # Marker position (percent) for the focal picker; nil focal defaults to center.
  defp focal_pct(nil), do: 50
  defp focal_pct(v) when is_number(v), do: Float.round(v * 100.0, 2)
end
