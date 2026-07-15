defmodule BbhWeb.Admin.PageLive.Form do
  use BbhWeb, :live_view

  alias Bbh.Content
  alias Bbh.Content.{Page, Blocks}
  alias Bbh.Media

  @statuses [{"Entwurf", "draft"}, {"Veröffentlicht", "published"}]
  @block_types [
    {"Text", "richtext"},
    {"Hinweis", "alert"},
    {"Bild-Karte", "media_card"},
    {"Galerie", "image_gallery"},
    {"Personenliste", "person_list"}
  ]

  @impl true
  def mount(params, _session, socket) do
    socket =
      socket
      |> assign(statuses: @statuses, block_types: @block_types)
      |> assign(image_picker_for: nil, media_search: "")
      |> assign(media_library: Media.list_uploads(images_only: true))

    {:ok, apply_action(socket, socket.assigns.live_action, params)}
  end

  defp apply_action(socket, :new, _params) do
    socket
    |> assign(page_title: "Neue Seite", page: %Page{status: "draft"}, blocks: [])
    |> assign_meta_form(Content.change_page(%Page{status: "draft"}))
  end

  defp apply_action(socket, :edit, %{"id" => id}) do
    page = Content.get_page!(id)

    socket
    |> assign(page_title: "Seite bearbeiten", page: page, blocks: Content.load_blocks(page))
    |> assign_meta_form(Content.change_page(page))
  end

  @impl true
  def handle_event("validate_page", %{"page" => params}, socket) do
    changeset = socket.assigns.page |> Content.change_page(params) |> Map.put(:action, :validate)
    {:noreply, assign_meta_form(socket, changeset)}
  end

  def handle_event("save_page", %{"page" => params}, socket) do
    save_page(socket, socket.assigns.live_action, params)
  end

  def handle_event("delete", %{"confirm" => confirm}, socket) do
    page = socket.assigns.page

    cond do
      not BbhWeb.Authz.can_delete?(socket.assigns.current_scope.user, page) ->
        {:noreply, put_flash(socket, :error, "Keine Berechtigung zum Löschen.")}

      confirm == page.slug ->
        {:ok, _} = Content.delete_page(page)

        {:noreply,
         socket |> put_flash(:info, "Seite gelöscht.") |> push_navigate(to: ~p"/admin/seiten")}

      true ->
        {:noreply, put_flash(socket, :error, "Der eingegebene Wert stimmt nicht überein.")}
    end
  end

  def handle_event("add_block", %{"type" => type}, socket) do
    {:ok, _} = Content.add_block(socket.assigns.page, type)
    {:noreply, reload_blocks(socket)}
  end

  def handle_event("save_block", %{"pb_id" => pb_id, "block" => params}, socket) do
    pb = find_pb(socket, pb_id)

    case Content.update_block(pb, normalize_block(pb.block_type, params)) do
      {:ok, _} ->
        {:noreply, socket |> put_flash(:info, "Block gespeichert.") |> reload_blocks()}

      {:error, _} ->
        {:noreply, put_flash(socket, :error, "Block konnte nicht gespeichert werden.")}
    end
  end

  def handle_event("delete_block", %{"pb_id" => pb_id}, socket) do
    socket |> find_pb(pb_id) |> Content.delete_block()
    {:noreply, reload_blocks(socket)}
  end

  def handle_event("open_image_picker", %{"pb_id" => pb_id}, socket),
    do: {:noreply, assign(socket, image_picker_for: pb_id, media_search: "")}

  def handle_event("close_image_picker", _params, socket),
    do: {:noreply, assign(socket, :image_picker_for, nil)}

  def handle_event("search_media", %{"search" => search}, socket) do
    {:noreply,
     socket
     |> assign(media_search: search)
     |> assign(media_library: Media.list_uploads(images_only: true, search: search))}
  end

  def handle_event("set_block_image", %{"pb_id" => pb_id, "media_id" => media_id}, socket) do
    {:ok, _} = Content.update_block(find_pb(socket, pb_id), %{"image_id" => media_id})
    {:noreply, socket |> assign(:image_picker_for, nil) |> reload_blocks()}
  end

  def handle_event("clear_block_image", %{"pb_id" => pb_id}, socket) do
    {:ok, _} = Content.update_block(find_pb(socket, pb_id), %{"image_id" => nil})
    {:noreply, reload_blocks(socket)}
  end

  def handle_event("move", %{"pb_id" => pb_id, "dir" => dir}, socket) do
    direction = if dir == "up", do: :up, else: :down

    case Content.move_block(socket.assigns.page.id, find_pb(socket, pb_id), direction) do
      {:ok, _} ->
        {:noreply, reload_blocks(socket)}

      {:error, _reason} ->
        {:noreply, put_flash(socket, :error, "Block konnte nicht verschoben werden.")}
    end
  end

  defp save_page(socket, :new, params) do
    case Content.create_page(params) do
      {:ok, page} ->
        {:noreply,
         socket
         |> put_flash(:info, "Seite erstellt. Jetzt Blöcke hinzufügen.")
         |> push_navigate(to: ~p"/admin/seiten/#{page.id}/bearbeiten")}

      {:error, changeset} ->
        {:noreply, assign_meta_form(socket, changeset)}
    end
  end

  defp save_page(socket, :edit, params) do
    case Content.update_page(socket.assigns.page, params) do
      {:ok, page} ->
        {:noreply, socket |> assign(:page, page) |> put_flash(:info, "Seite gespeichert.")}

      {:error, changeset} ->
        {:noreply, assign_meta_form(socket, changeset)}
    end
  end

  defp reload_blocks(socket) do
    page = Content.get_page!(socket.assigns.page.id)
    assign(socket, page: page, blocks: Content.load_blocks(page))
  end

  defp find_pb(socket, pb_id) do
    Enum.find_value(socket.assigns.blocks, fn {pb, _} -> pb.id == pb_id && pb end)
  end

  defp assign_meta_form(socket, changeset),
    do: assign(socket, :form, to_form(changeset, as: "page"))

  # Per-type param massaging before the block changeset.
  defp normalize_block("person_list", params) do
    Map.update(params, "filter_roles", [], fn
      roles when is_list(roles) -> Enum.reject(roles, &(&1 == ""))
      _ -> []
    end)
  end

  defp normalize_block(_type, params), do: params

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.admin flash={@flash} current_scope={@current_scope} active={:pages}>
      <.header>
        {@page_title}
        <:actions>
          <.button navigate={~p"/admin/seiten"}>Zurück</.button>
        </:actions>
      </.header>

      <.form
        for={@form}
        id="page-form"
        phx-change="validate_page"
        phx-submit="save_page"
        class="mt-6 space-y-4"
      >
        <.input field={@form[:title]} label="Titel" required />
        <.input field={@form[:slug]} label="Slug" required />
        <.input field={@form[:status]} type="select" label="Status" options={@statuses} />
        <.input field={@form[:sort_order]} type="number" label="Sortierung" />
        <.button variant="primary" phx-disable-with="Speichern…">Seite speichern</.button>
      </.form>

      <section :if={@live_action == :edit} class="mt-10">
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

            <.media_card_image
              :if={pb.block_type == "media_card"}
              pb={pb}
              block={block}
              open={@image_picker_for == pb.id}
              media_library={@media_library}
              media_search={@media_search}
            />

            <.form :let={f} for={block_form(pb, block)} id={"block-#{pb.id}"} phx-submit="save_block">
              <input type="hidden" name="pb_id" value={pb.id} />
              <.block_fields type={pb.block_type} f={f} block={block} />
              <.button variant="primary" class="btn btn-primary btn-sm mt-2" phx-disable-with="…">Block speichern</.button>
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

      <.danger_zone
        :if={@live_action == :edit and BbhWeb.Authz.can_delete?(@current_scope.user, @page)}
        confirm_value={@page.slug}
      >
        Die Seite „{@page.title}" und alle ihre Blöcke werden dauerhaft gelöscht.
      </.danger_zone>
    </Layouts.admin>
    """
  end

  # Per-type block field sets.
  attr :type, :string, required: true
  attr :f, :map, required: true
  attr :block, :any, required: true

  defp block_fields(%{type: "richtext"} = assigns) do
    ~H"""
    <.rich_text field={@f[:body]} label="Text" />
    """
  end

  defp block_fields(%{type: "alert"} = assigns) do
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

  defp block_fields(%{type: "media_card"} = assigns) do
    ~H"""
    <.input field={@f[:title]} label="Titel" />
    <.input field={@f[:subtitle]} label="Untertitel" />
    <.input
      field={@f[:image_position]}
      type="select"
      label="Bildposition"
      options={[{"Rechts", "right"}, {"Links", "left"}]}
    />
    <.rich_text field={@f[:body]} label="Text" />
    """
  end

  defp block_fields(%{type: "image_gallery"} = assigns) do
    ~H"""
    <.input field={@f[:title]} label="Titel" />
    <.input
      field={@f[:layout]}
      type="select"
      label="Layout"
      options={[{"Raster", "grid"}, {"Diashow", "slideshow"}]}
    />
    <.input field={@f[:lightbox]} type="checkbox" label="Lightbox aktivieren" />
    <p class="text-xs text-base-content/50">Bilderverwaltung folgt über die Medienbibliothek.</p>
    """
  end

  defp block_fields(%{type: "person_list"} = assigns) do
    ~H"""
    <.input field={@f[:title]} label="Titel" />
    <.input
      field={@f[:display_style]}
      type="select"
      label="Darstellung"
      options={[{"Tabelle", "table"}, {"Karten", "cards"}, {"Kompakt", "compact"}]}
    />
    <.input
      field={@f[:filter_honorary]}
      type="select"
      label="Ehrenmitglieder"
      options={[{"Alle", "all"}, {"Nur Ehrenmitglieder", "only"}, {"Ohne Ehrenmitglieder", "exclude"}]}
    />
    <.input field={@f[:show_address]} type="checkbox" label="Adresse anzeigen" />
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

  # Image selection for a media_card block. Rendered outside the block's <.form> so
  # its buttons/search don't submit that form; changes persist immediately.
  attr :pb, :map, required: true
  attr :block, :any, required: true
  attr :open, :boolean, required: true
  attr :media_library, :list, required: true
  attr :media_search, :string, required: true

  defp media_card_image(assigns) do
    ~H"""
    <div class="mb-3 rounded-box bg-base-200/50 p-3">
      <div class="flex items-center gap-3">
        <img
          :if={@block.image}
          src={media_url(@block.image, width: 160, height: 100)}
          alt=""
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
            phx-click="open_image_picker"
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

      <div :if={@open} class="mt-3">
        <form phx-change="search_media" id={"media-card-search-#{@pb.id}"} class="mb-2">
          <input
            type="text"
            name="search"
            value={@media_search}
            placeholder="Mediathek durchsuchen…"
            phx-debounce="300"
            class="input input-bordered input-sm w-full max-w-xs"
          />
        </form>
        <div class="grid max-h-64 grid-cols-3 gap-2 overflow-y-auto rounded-box border border-base-300 p-2 sm:grid-cols-4 md:grid-cols-6">
          <button
            :for={m <- @media_library}
            type="button"
            phx-click="set_block_image"
            phx-value-pb_id={@pb.id}
            phx-value-media_id={m.id}
            title={m.filename}
            class="group relative"
          >
            <img
              src={media_url(m, width: 120, height: 120)}
              alt={m.filename}
              class="aspect-square w-full rounded object-cover"
            />
            <span class="absolute inset-0 flex items-center justify-center rounded bg-black/50 text-xs text-white opacity-0 group-hover:opacity-100">
              wählen
            </span>
          </button>
          <p :if={@media_library == []} class="col-span-full p-2 text-sm text-base-content/60">
            Keine Bilder gefunden.
          </p>
        </div>
        <button type="button" phx-click="close_image_picker" class="btn btn-ghost btn-xs mt-2">
          Schließen
        </button>
      </div>
    </div>
    """
  end

  defp block_form(pb, block) do
    # Namespace field ids per block so multiple Trix editors don't collide.
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
  defp block_label(other), do: other
end
