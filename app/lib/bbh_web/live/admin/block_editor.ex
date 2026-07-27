defmodule BbhWeb.Admin.BlockEditor do
  @moduledoc """
  Shared admin editor for content blocks (the Directus M2A `block_*` tables), used by
  both the page form and the article form. Renders the whole "Inhaltsblöcke" section:
  the ordered block list with its move/delete controls, each block's field form, the
  media pickers for `media_card`/`image_gallery` blocks, and the "add block" form.

  The host LiveView owns the state and the event handlers (`add_block`, `save_block`,
  `move`, `delete_block`, `clear_block_image`, `remove_gallery_file`, `move_gallery_file`,
  and the `{:media_selected, …}` picks) so the same markup drives either owner. The host
  also mounts the shared `BbhWeb.Admin.MediaPicker` (id `media-picker`) that the block
  image buttons target. Expects `@blocks` — the `{block_join, block_struct}` tuples from
  `Bbh.Content.load_blocks/1`.
  """
  use BbhWeb, :html

  alias Bbh.Content.Blocks

  @block_types [
    {"Text", "richtext"},
    {"Hinweis", "alert"},
    {"Bild-Karte", "media_card"},
    {"Galerie", "image_gallery"},
    {"Personenliste", "person_list"},
    {"Trennlinie", "separator"}
  ]

  @doc "The block types offered in the add-block picker as `{label, value}` tuples."
  def block_types, do: @block_types

  @doc """
  Per-type param massaging before the block changeset. `person_list` drops the empty
  hidden option kept so an all-unchecked roles list still submits the field.
  """
  def normalize_block("person_list", params) do
    Map.update(params, "filter_roles", [], fn
      roles when is_list(roles) -> Enum.reject(roles, &(&1 == ""))
      _ -> []
    end)
  end

  def normalize_block(_type, params), do: params

  @doc "The full block-editor section for a page or article."
  attr :blocks, :list, required: true

  def block_editor(assigns) do
    assigns = assign(assigns, :block_types, @block_types)

    ~H"""
    <section class="mt-10">
      <h2 class="text-xl font-semibold">Inhaltsblöcke</h2>

      <div class="mt-4 space-y-4">
        <div
          :for={{{pb, block}, i} <- Enum.with_index(@blocks)}
          class="rounded-box border border-base-300 p-4"
        >
          <div class="mb-3 flex items-center justify-between">
            <span class="badge badge-neutral">{block_label(pb.block_type)}</span>
            <div class="flex gap-1">
              <button
                type="button"
                class="btn btn-ghost btn-xs"
                phx-click="move"
                phx-value-pb_id={pb.id}
                phx-value-dir="up"
                disabled={i == 0}
              >↑</button>
              <button
                type="button"
                class="btn btn-ghost btn-xs"
                phx-click="move"
                phx-value-pb_id={pb.id}
                phx-value-dir="down"
                disabled={i == length(@blocks) - 1}
              >↓</button>
              <button
                type="button"
                class="btn btn-ghost btn-xs text-error"
                phx-click="delete_block"
                phx-value-pb_id={pb.id}
                data-confirm="Block löschen?"
              >✕</button>
            </div>
          </div>

          <%!-- Image management sits outside the block's <.form> so its buttons can't
                submit it; every change persists immediately. --%>
          <.media_card_image :if={pb.block_type == "media_card"} pb={pb} block={block} />
          <.gallery_files :if={pb.block_type == "image_gallery"} pb={pb} block={block} />

          <.form :let={f} for={block_form(pb, block)} id={"block-#{pb.id}"} phx-submit="save_block">
            <input type="hidden" name="pb_id" value={pb.id} />
            <.block_fields type={pb.block_type} f={f} block={block} />
            <.button variant="primary" class="btn btn-primary btn-sm mt-2" phx-disable-with="…">
              Block speichern
            </.button>
          </.form>
        </div>

        <p :if={@blocks == []} class="text-base-content/60">Noch keine Blöcke.</p>
      </div>

      <form phx-submit="add_block" class="mt-4 flex items-end gap-2">
        <label class="fieldset">
          <span class="label mb-1">Block hinzufügen</span>
          <select name="type" class="select select-bordered">
            <option :for={{label, value} <- @block_types} value={value}>{label}</option>
          </select>
        </label>
        <.button variant="primary">Hinzufügen</.button>
      </form>
    </section>
    """
  end

  # Per-type block field sets.
  attr :type, :string, required: true
  attr :f, :map, required: true
  attr :block, :any, required: true

  def block_fields(%{type: "richtext"} = assigns) do
    ~H"""
    <.rich_text field={@f[:body]} label="Text" />
    """
  end

  def block_fields(%{type: "alert"} = assigns) do
    ~H"""
    <.input
      field={@f[:icon]}
      type="select"
      label="Symbol"
      options={[{"Info", "info"}, {"Warnung", "warning"}, {"Erfolg", "success"}, {"Gefahr", "danger"}]}
    />
    <.rich_text field={@f[:body]} label="Text" />
    """
  end

  def block_fields(%{type: "media_card"} = assigns) do
    ~H"""
    <.input field={@f[:title]} label="Titel" />
    <.input field={@f[:subtitle]} label="Untertitel" />
    <.input
      field={@f[:image_position]}
      type="select"
      label="Bildposition"
      options={[{"Rechts", "right"}, {"Links", "left"}]}
    />
    <.input field={@f[:title_above]} type="checkbox" label="Titel über dem Bild anzeigen" />
    <.input field={@f[:show_credit]} type="checkbox" label="Bildunterschrift und Copyright anzeigen" />
    <.input field={@f[:shadow]} type="checkbox" label="Als Karte mit Schatten darstellen" />
    <.rich_text field={@f[:body]} label="Text" />
    """
  end

  def block_fields(%{type: "image_gallery"} = assigns) do
    assigns = assign(assigns, :aspect_ratios, aspect_ratio_options())

    ~H"""
    <.input field={@f[:title]} label="Titel" />
    <.input
      field={@f[:layout]}
      type="select"
      label="Layout"
      options={[{"Raster", "grid"}, {"Diashow", "slideshow"}]}
    />
    <%!-- Shown whatever the layout is: the form saves in one go, so hiding these until
          „Diashow" has been stored would cost a save before they could be set. --%>
    <.input
      field={@f[:aspect_ratio]}
      type="select"
      label="Seitenverhältnis der Diashow"
      options={@aspect_ratios}
    />
    <.input field={@f[:lightbox]} type="checkbox" label="Lightbox aktivieren" />
    <.input field={@f[:autoplay]} type="checkbox" label="Diashow automatisch weiterblättern" />
    """
  end

  def block_fields(%{type: "person_list"} = assigns) do
    ~H"""
    <.input field={@f[:title]} label="Titel" />
    <.input
      field={@f[:display_style]}
      type="select"
      label="Darstellung"
      options={display_style_options()}
    />
    <.input field={@f[:sort_by]} type="select" label="Sortierung" options={sort_by_options()} />
    <.input
      field={@f[:filter_honorary]}
      type="select"
      label="Ehrenmitglieder"
      options={[{"Alle", "all"}, {"Nur Ehrenmitglieder", "only"}, {"Ohne Ehrenmitglieder", "exclude"}]}
    />
    <.input
      field={@f[:only_active]}
      type="checkbox"
      label="Nur aktive Personen (ohne „Amt bis“)"
    />
    <.input field={@f[:show_address]} type="checkbox" label="Adresse anzeigen (nur Tabelle)" />
    <fieldset class="fieldset">
      <legend class="label mb-1">Rollen (leer = alle)</legend>
      <input type="hidden" name="block[filter_roles][]" value="" />
      <div class="grid grid-cols-2 gap-1 sm:grid-cols-3">
        <label :for={role <- Bbh.Club.Person.roles()} class="flex items-center gap-2 text-sm">
          <input
            type="checkbox"
            name="block[filter_roles][]"
            value={role}
            checked={role in @block.filter_roles}
            class="checkbox checkbox-sm"
          />
          {Bbh.Club.Person.role_label(role)}
        </label>
      </div>
    </fieldset>
    """
  end

  def block_fields(%{type: "separator"} = assigns) do
    ~H"""
    <p class="text-sm text-base-content/60">Horizontale Trennlinie – keine Einstellungen.</p>
    """
  end

  # Same reasoning as the ratios below: read off the schema so the dropdown cannot offer a
  # style the changeset rejects. „Kompakt" survived precisely because these two lists were
  # maintained by hand and drifted.
  @display_style_labels %{"table" => "Tabelle", "cards" => "Karten"}

  defp display_style_options do
    for style <- Blocks.PersonList.styles(),
        do: {@display_style_labels[style] || style, style}
  end

  # Same read-off-the-schema contract as display styles above.
  @sort_by_labels %{"sort_order" => "Reihenfolge (manuell)", "year_start" => "Amtsantritt (Jahr)"}

  defp sort_by_options do
    for k <- Blocks.PersonList.sort_bys(), do: {@sort_by_labels[k] || k, k}
  end

  # Read off the schema so the dropdown cannot offer a ratio the changeset rejects. A
  # ratio without a label here still shows up, as its bare „W:H".
  @aspect_ratio_labels %{
    "16:9" => "Breitbild",
    "3:2" => "Kamera, quer",
    "4:3" => "Klassisch, quer",
    "1:1" => "Quadratisch",
    "3:4" => "Klassisch, hoch",
    "2:3" => "Kamera, hoch",
    "9:16" => "Hochformat"
  }

  defp aspect_ratio_options do
    for ratio <- Blocks.ImageGallery.aspect_ratios() do
      case @aspect_ratio_labels[ratio] do
        nil -> {ratio, ratio}
        label -> {"#{ratio} · #{label}", ratio}
      end
    end
  end

  # The single image of a media_card block.
  attr :pb, :map, required: true
  attr :block, :any, required: true

  def media_card_image(assigns) do
    ~H"""
    <div class="mb-3 rounded-box bg-base-200/50 p-3">
      <div class="flex items-center gap-3">
        <img
          :if={@block.image}
          src={media_url(@block.image, width: 160, height: 100)}
          alt={image_alt(@block.image)}
          class="aspect-video w-28 rounded object-cover"
        />
        <span
          :if={is_nil(@block.image)}
          class="flex aspect-video w-28 items-center justify-center rounded bg-base-300 text-xs text-base-content/60"
        >
          Kein Bild
        </span>
        <div class="flex flex-wrap gap-2">
          <button
            type="button"
            phx-click="open"
            phx-target="#media-picker"
            phx-value-context="media_card"
            phx-value-pb_id={@pb.id}
            class="btn btn-outline btn-sm"
          >
            {if @block.image, do: "Bild ändern", else: "Bild wählen"}
          </button>
          <button
            :if={@block.image}
            type="button"
            phx-click="clear_block_image"
            phx-value-pb_id={@pb.id}
            class="btn btn-ghost btn-sm text-error"
          >
            Entfernen
          </button>
        </div>
      </div>
    </div>
    """
  end

  # The images of a gallery block, in display order.
  attr :pb, :map, required: true
  attr :block, :any, required: true

  def gallery_files(assigns) do
    ~H"""
    <div class="mb-3 rounded-box bg-base-200/50 p-3">
      <p class="mb-2 text-sm font-medium">Bilder ({length(@block.files)})</p>

      <div :if={@block.files != []} class="grid grid-cols-2 gap-2 sm:grid-cols-3 md:grid-cols-4">
        <div
          :for={{file, i} <- Enum.with_index(@block.files)}
          class="overflow-hidden rounded border border-base-300 bg-base-100"
        >
          <img
            src={media_url(file.media, width: 200, height: 200)}
            alt={image_alt(file)}
            loading="lazy"
            class="aspect-square w-full object-cover"
          />
          <p class="truncate px-1.5 pt-1 text-xs" title={file.media.filename}>
            {image_caption(file.media) || file.media.title || file.media.filename}
          </p>
          <div class="flex items-center justify-between px-1 pb-1">
            <div class="flex">
              <button
                type="button"
                class="btn btn-ghost btn-xs"
                phx-click="move_gallery_file"
                phx-value-file_id={file.id}
                phx-value-dir="up"
                disabled={i == 0}
                aria-label="Nach vorne"
              >↑</button>
              <button
                type="button"
                class="btn btn-ghost btn-xs"
                phx-click="move_gallery_file"
                phx-value-file_id={file.id}
                phx-value-dir="down"
                disabled={i == length(@block.files) - 1}
                aria-label="Nach hinten"
              >↓</button>
            </div>
            <button
              type="button"
              class="btn btn-ghost btn-xs text-error"
              phx-click="remove_gallery_file"
              phx-value-file_id={file.id}
              data-confirm="Bild aus der Galerie entfernen?"
              aria-label="Entfernen"
            >✕</button>
          </div>
        </div>
      </div>

      <button
        type="button"
        phx-click="open"
        phx-target="#media-picker"
        phx-value-context="gallery"
        phx-value-pb_id={@pb.id}
        class="btn btn-outline btn-sm mt-2 gap-1"
      >
        <.icon name="hero-photo" class="size-4" /> Bild hinzufügen
      </button>
      <p class="mt-1 text-xs text-base-content/60">
        Bildunterschrift und Copyright kommen aus der
        <.link navigate={~p"/admin/medien"} class="link">Mediathek</.link>
        — im Raster beim Vergrößern, in der Diashow direkt unter dem Bild.
      </p>
    </div>
    """
  end

  # Namespace field ids per block so multiple Quill editors don't collide.
  defp block_form(pb, block) do
    to_form(Blocks.schema_for(pb.block_type).changeset(block, %{}),
      as: "block",
      id: "block-#{pb.id}"
    )
  end

  defp block_label("richtext"), do: "Text"
  defp block_label("alert"), do: "Hinweis"
  defp block_label("media_card"), do: "Bild-Karte"
  defp block_label("image_gallery"), do: "Galerie"
  defp block_label("person_list"), do: "Personenliste"
  defp block_label("separator"), do: "Trennlinie"
  defp block_label(other), do: other
end
