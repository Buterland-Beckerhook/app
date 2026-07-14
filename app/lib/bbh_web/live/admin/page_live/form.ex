defmodule BbhWeb.Admin.PageLive.Form do
  use BbhWeb, :live_view

  alias Bbh.Content
  alias Bbh.Content.{Page, Blocks}

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
    socket = assign(socket, statuses: @statuses, block_types: @block_types)
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

  def handle_event("add_block", %{"type" => type}, socket) do
    {:ok, _} = Content.add_block(socket.assigns.page, type)
    {:noreply, reload_blocks(socket)}
  end

  def handle_event("save_block", %{"pb_id" => pb_id, "block" => params}, socket) do
    pb = find_pb(socket, pb_id)

    case Content.update_block(pb, normalize_block(pb.block_type, params)) do
      {:ok, _} -> {:noreply, socket |> put_flash(:info, "Block gespeichert.") |> reload_blocks()}
      {:error, _} -> {:noreply, put_flash(socket, :error, "Block konnte nicht gespeichert werden.")}
    end
  end

  def handle_event("delete_block", %{"pb_id" => pb_id}, socket) do
    socket |> find_pb(pb_id) |> Content.delete_block()
    {:noreply, reload_blocks(socket)}
  end

  def handle_event("move", %{"pb_id" => pb_id, "dir" => dir}, socket) do
    direction = if dir == "up", do: :up, else: :down
    Content.move_block(socket.assigns.page.id, find_pb(socket, pb_id), direction)
    {:noreply, reload_blocks(socket)}
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

  defp assign_meta_form(socket, changeset), do: assign(socket, :form, to_form(changeset, as: "page"))

  # Per-type param massaging before the block changeset.
  defp normalize_block("person_list", params) do
    Map.update(params, "filter_roles", [], fn
      roles when is_binary(roles) ->
        roles |> String.split(",") |> Enum.map(&String.trim/1) |> Enum.reject(&(&1 == ""))

      roles ->
        roles
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

      <.form for={@form} id="page-form" phx-change="validate_page" phx-submit="save_page" class="mt-6 space-y-4">
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
                <button type="button" class="btn btn-ghost btn-xs" phx-click="move" phx-value-pb_id={pb.id} phx-value-dir="up" disabled={i == 0}>↑</button>
                <button type="button" class="btn btn-ghost btn-xs" phx-click="move" phx-value-pb_id={pb.id} phx-value-dir="down" disabled={i == length(@blocks) - 1}>↓</button>
                <button type="button" class="btn btn-ghost btn-xs text-error" phx-click="delete_block" phx-value-pb_id={pb.id} data-confirm="Block löschen?">✕</button>
              </div>
            </div>

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
    <.input field={@f[:icon]} type="select" label="Symbol" options={[{"Info", "info"}, {"Warnung", "warning"}, {"Erfolg", "success"}, {"Gefahr", "danger"}]} />
    <.rich_text field={@f[:body]} label="Text" />
    """
  end

  defp block_fields(%{type: "media_card"} = assigns) do
    ~H"""
    <.input field={@f[:title]} label="Titel" />
    <.input field={@f[:subtitle]} label="Untertitel" />
    <.input field={@f[:image_position]} type="select" label="Bildposition" options={[{"Rechts", "right"}, {"Links", "left"}]} />
    <.rich_text field={@f[:body]} label="Text" />
    <p class="text-xs text-base-content/50">Bildauswahl folgt über die Medienbibliothek.</p>
    """
  end

  defp block_fields(%{type: "image_gallery"} = assigns) do
    ~H"""
    <.input field={@f[:title]} label="Titel" />
    <.input field={@f[:layout]} type="select" label="Layout" options={[{"Raster", "grid"}, {"Diashow", "slideshow"}]} />
    <.input field={@f[:lightbox]} type="checkbox" label="Lightbox aktivieren" />
    <p class="text-xs text-base-content/50">Bilderverwaltung folgt über die Medienbibliothek.</p>
    """
  end

  defp block_fields(%{type: "person_list"} = assigns) do
    ~H"""
    <.input field={@f[:title]} label="Titel" />
    <.input field={@f[:display_style]} type="select" label="Darstellung" options={[{"Tabelle", "table"}, {"Karten", "cards"}, {"Kompakt", "compact"}]} />
    <.input field={@f[:filter_honorary]} type="select" label="Ehrenmitglieder" options={[{"Alle", "all"}, {"Nur Ehrenmitglieder", "only"}, {"Ohne Ehrenmitglieder", "exclude"}]} />
    <.input field={@f[:show_address]} type="checkbox" label="Adresse anzeigen" />
    <.input name="block[filter_roles]" id={"roles-#{@block.id}"} value={Enum.join(@block.filter_roles, ", ")} label="Rollen (kommagetrennt, z. B. praesident, oberst)" />
    """
  end

  defp block_form(pb, block) do
    # Namespace field ids per block so multiple Trix editors don't collide.
    to_form(Blocks.schema_for(pb.block_type).changeset(block, %{}), as: "block", id: "block-#{pb.id}")
  end

  defp block_label("richtext"), do: "Text"
  defp block_label("alert"), do: "Hinweis"
  defp block_label("media_card"), do: "Bild-Karte"
  defp block_label("image_gallery"), do: "Galerie"
  defp block_label("person_list"), do: "Personenliste"
  defp block_label(other), do: other
end
