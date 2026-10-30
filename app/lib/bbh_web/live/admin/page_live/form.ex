defmodule BbhWeb.Admin.PageLive.Form do
  use BbhWeb, :live_view

  alias Bbh.Content
  alias Bbh.Content.Page
  import BbhWeb.Admin.BlockEditor, only: [block_editor: 1, normalize_block: 2, move_direction: 1]

  @statuses [{"Entwurf", "draft"}, {"Veröffentlicht", "published"}]

  @placements [
    {"Im Verein-Menü", "menu"},
    {"Nur per Link (/seite/…)", "unlisted"},
    {"Sonderseite (von der Website eingebunden)", "system"}
  ]

  @impl true
  def mount(params, _session, socket) do
    socket = assign(socket, statuses: @statuses, placements: @placements)

    {:ok, apply_action(socket, socket.assigns.live_action, params)}
  end

  defp apply_action(socket, :new, _params) do
    page = %Page{status: "draft"}

    socket
    |> assign(page_title: "Neue Seite", page: page, blocks: [])
    |> assign(parent_options: parent_options(page))
    |> assign_meta_form(Content.Pages.change_page(page))
  end

  defp apply_action(socket, :edit, %{"id" => id}) do
    page = Content.Pages.get_page!(id)

    socket
    |> assign(page_title: "Seite bearbeiten", page: page, blocks: Content.load_blocks(page))
    |> assign(parent_options: parent_options(page))
    |> assign_meta_form(Content.Pages.change_page(page))
  end

  @impl true
  def handle_event("validate_page", %{"page" => params}, socket) do
    changeset =
      socket.assigns.page |> Content.Pages.change_page(params) |> Map.put(:action, :validate)

    {:noreply, assign_meta_form(socket, changeset)}
  end

  def handle_event("save_page", %{"page" => params}, socket) do
    save_page(socket, socket.assigns.live_action, params)
  end

  def handle_event("delete", %{"confirm" => confirm}, socket) do
    page = socket.assigns.page

    cond do
      not Bbh.Authz.can_delete?(socket.assigns.current_scope.user, page) ->
        {:noreply, put_flash(socket, :error, "Keine Berechtigung zum Löschen.")}

      confirm == page.slug ->
        {:ok, _} = Content.Pages.delete_page(socket.assigns.current_scope, page)

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

  def handle_event("clear_block_image", %{"pb_id" => pb_id}, socket) do
    {:ok, _} = Content.update_block(find_pb(socket, pb_id), %{"image_id" => nil})
    {:noreply, reload_blocks(socket)}
  end

  def handle_event("remove_gallery_file", %{"file_id" => file_id}, socket) do
    {:ok, _} = file_id |> Content.get_gallery_file!() |> Content.delete_gallery_file()
    {:noreply, reload_blocks(socket)}
  end

  def handle_event("move_gallery_file", %{"file_id" => file_id, "dir" => dir}, socket) do
    file = Content.get_gallery_file!(file_id)
    direction = move_direction(dir)

    case Content.move_gallery_file(file.gallery_id, file, direction) do
      {:ok, _} ->
        {:noreply, reload_blocks(socket)}

      {:error, _reason} ->
        {:noreply, put_flash(socket, :error, "Bild konnte nicht verschoben werden.")}
    end
  end

  def handle_event("move", %{"pb_id" => pb_id, "dir" => dir}, socket) do
    direction = move_direction(dir)

    case Content.move_block(find_pb(socket, pb_id), direction) do
      {:ok, _} ->
        {:noreply, reload_blocks(socket)}

      {:error, _reason} ->
        {:noreply, put_flash(socket, :error, "Block konnte nicht verschoben werden.")}
    end
  end

  # Picks from the shared media picker (BbhWeb.Admin.MediaPicker). The `pb_id` the modal
  # was opened with tells us which block the choice belongs to.
  @impl true
  def handle_info({:media_selected, %{"context" => "media_card", "pb_id" => pb_id}, id}, socket) do
    case find_pb(socket, pb_id) do
      nil ->
        {:noreply, put_flash(socket, :error, "Dieser Block existiert nicht mehr.")}

      pb ->
        {:ok, _} = Content.update_block(pb, %{"image_id" => id})
        {:noreply, reload_blocks(socket)}
    end
  end

  def handle_info({:media_selected, %{"context" => "gallery", "pb_id" => pb_id}, id}, socket) do
    # The block can be gone by the time the pick lands (deleted here or in another tab),
    # and a MatchError here would take the whole editor — and every unsaved block — down.
    case find_block(socket, pb_id) do
      {_pb, gallery} ->
        {:ok, _} = Content.add_gallery_file(gallery, id)
        {:noreply, reload_blocks(socket)}

      nil ->
        {:noreply, put_flash(socket, :error, "Dieser Block existiert nicht mehr.")}
    end
  end

  defp save_page(socket, :new, params) do
    case Content.Pages.create_page(params) do
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
    case Content.Pages.update_page(socket.assigns.page, params) do
      {:ok, page} ->
        {:noreply, socket |> assign(:page, page) |> put_flash(:info, "Seite gespeichert.")}

      {:error, changeset} ->
        {:noreply, assign_meta_form(socket, changeset)}
    end
  end

  defp reload_blocks(socket) do
    page = Content.Pages.get_page!(socket.assigns.page.id)
    assign(socket, page: page, blocks: Content.load_blocks(page))
  end

  defp find_pb(socket, pb_id) do
    Enum.find_value(socket.assigns.blocks, fn {pb, _} -> pb.id == pb_id && pb end)
  end

  defp find_block(socket, pb_id) do
    Enum.find(socket.assigns.blocks, fn {pb, _} -> pb.id == pb_id end)
  end

  defp assign_meta_form(socket, changeset) do
    assign(socket,
      form: to_form(changeset, as: "page"),
      has_parent: Ecto.Changeset.get_field(changeset, :parent_id) not in [nil, ""],
      url_hint: url_hint(changeset)
    )
  end

  # Where the page will be served (independent of its publication status), so
  # editors can copy the address of an unlisted page into an event or article.
  defp url_hint(changeset) do
    slug = Ecto.Changeset.get_field(changeset, :slug)
    parent_id = Ecto.Changeset.get_field(changeset, :parent_id)

    cond do
      slug in [nil, ""] ->
        nil

      parent_id not in [nil, ""] ->
        with %Page{} = parent <- Content.Pages.get_page(parent_id),
             path when is_binary(path) <- Content.Pages.public_path(parent) do
          {:path, path <> "/" <> slug}
        else
          _ -> nil
        end

      true ->
        page = Ecto.Changeset.apply_changes(changeset)

        case Content.Pages.public_path(%{page | parent_id: nil}) do
          nil -> :embedded
          path -> {:path, path}
        end
    end
  end

  defp site_url, do: Application.get_env(:bbh, :site_url, "https://buterland-beckerhook.de")

  # Parent picker options as "Root / Child" labels, excluding the page itself and
  # its descendants (so a page can't become its own ancestor) and anything outside
  # the menu tree (only menu pages nest).
  defp parent_options(page) do
    pages = Content.Pages.list_pages()
    by_id = Map.new(pages, &{&1.id, &1})
    excluded = descendant_ids(page.id, pages)

    pages
    |> Enum.reject(&(&1.id in excluded))
    |> Enum.filter(&(root_of(&1, by_id).placement == "menu"))
    |> Enum.map(fn p -> {label_path(p, by_id), p.id} end)
    |> Enum.sort_by(fn {label, _id} -> label end)
  end

  defp descendant_ids(nil, _pages), do: []

  defp descendant_ids(id, pages) do
    children = Enum.group_by(pages, & &1.parent_id)
    collect_ids([id], children, MapSet.new()) |> MapSet.to_list()
  end

  defp collect_ids([], _children, acc), do: acc

  defp collect_ids([id | rest], children, acc) do
    kids = children |> Map.get(id, []) |> Enum.map(& &1.id)
    collect_ids(rest ++ kids, children, MapSet.put(acc, id))
  end

  defp root_of(%{parent_id: nil} = page, _by_id), do: page

  defp root_of(%{parent_id: pid} = page, by_id) do
    case Map.get(by_id, pid) do
      nil -> page
      parent -> root_of(parent, by_id)
    end
  end

  defp label_path(page, by_id), do: page |> label_chain(by_id, [page.title]) |> Enum.join(" / ")

  defp label_chain(%{parent_id: nil}, _by_id, acc), do: acc

  defp label_chain(%{parent_id: pid}, by_id, acc) do
    case Map.get(by_id, pid) do
      nil -> acc
      parent -> label_chain(parent, by_id, [parent.title | acc])
    end
  end

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
        phx-hook="UnsavedChanges"
        phx-change="validate_page"
        phx-submit="save_page"
        class="mt-6 space-y-4"
      >
        <.input field={@form[:title]} label="Titel" required phx-hook="SlugFromTitle" />
        <.input field={@form[:slug]} label="Slug" required />
        <.input
          field={@form[:parent_id]}
          type="select"
          label="Elternseite"
          prompt="— Keine (Top-Level) —"
          options={@parent_options}
        />
        <.input field={@form[:status]} type="select" label="Status" options={@statuses} />
        <.input field={@form[:sort_order]} type="number" label="Sortierung" />
        <.input
          :if={!@has_parent}
          field={@form[:placement]}
          type="select"
          label="Platzierung"
          options={@placements}
        />
        <%!-- Child pages always live in their root's menu tree. --%>
        <.input :if={@has_parent} field={@form[:placement]} type="hidden" value="menu" />
        <.input
          field={@form[:noindex]}
          type="checkbox"
          label="Von Suchmaschinen ausschließen (noindex) – auch nicht in Sitemap und Website-Suche"
        />
        <p :if={@url_hint} id="page-url-hint" class="text-sm text-base-content/70">
          <%= case @url_hint do %>
            <% {:path, path} -> %>
              Adresse: <span class="font-mono select-all">{site_url()}{path}</span>
            <% :embedded -> %>
              Sonderseite: wird von der Website selbst eingebunden und hat keine eigene Adresse.
          <% end %>
        </p>
        <.button variant="primary" phx-disable-with="Speichern…">Seite speichern</.button>
      </.form>

      <.block_editor :if={@live_action == :edit} blocks={@blocks} />

      <.danger_zone
        :if={@live_action == :edit and Bbh.Authz.can_delete?(@current_scope.user, @page)}
        confirm_value={@page.slug}
      >
        Die Seite „{@page.title}" und alle ihre Blöcke werden dauerhaft gelöscht.
      </.danger_zone>
      <.live_component module={BbhWeb.Admin.MediaPicker} id="media-picker" />
    </Layouts.admin>
    """
  end
end
