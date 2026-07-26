defmodule BbhWeb.Admin.MediaLive.Index do
  use BbhWeb, :live_view

  import BbhWeb.Admin.MediaEditor, only: [media_editor: 1]

  alias Bbh.Media
  alias Bbh.Media.Folder
  alias Bbh.Media.Upload
  alias BbhWeb.Admin.MediaEditor

  @impl true
  def mount(_params, _session, socket) do
    socket =
      socket
      |> assign(page_title: "Medien", search: "", sort: "newest")
      |> assign(scope: :all, editing: nil, new_folder: false)
      # Assigned here and nowhere else: picking a folder is a patch, so anything set in
      # handle_params/3 is set again on every click in the tree — which would throw the
      # sorting mode away mid-drag and fold the branch the editor just opened.
      |> assign(edit_mode: false, expanded: MapSet.new())
      |> allow_upload(:files,
        accept: ~w(.jpg .jpeg .png .webp .gif .pdf),
        max_entries: 10,
        max_file_size: 20_000_000
      )

    {:ok, socket}
  end

  @impl true
  def handle_params(params, _uri, socket) do
    {:noreply,
     socket
     |> assign(scope: scope_from(params["folder"]), editing: nil, new_folder: false)
     |> reveal_scope()
     |> load_tree()
     |> load_items()}
  end

  # Three states the old single `folder` assign could not carry: the whole library,
  # the files nobody filed, and one folder. Absent means "Alle Medien" — an unknown or
  # deleted id falls back to it rather than 404ing on a link someone kept.
  defp scope_from(nil), do: :all
  defp scope_from("none"), do: :unfiled
  defp scope_from(id), do: Media.get_folder(id) || :all

  defp reveal_scope(socket), do: reveal_parent(socket, socket.assigns.scope)

  # Only a sub-folder can be out of sight, so its parent is unfolded. A top-level folder
  # is left as the editor had it: the row is visible either way, and its files are in the
  # grid regardless of whether the branch below it is open.
  defp reveal_parent(socket, %Folder{parent_id: parent_id}) when not is_nil(parent_id),
    do: assign(socket, :expanded, MapSet.put(socket.assigns.expanded, parent_id))

  defp reveal_parent(socket, _scope), do: socket

  defp load_tree(socket) do
    tree = Media.list_folder_tree()
    assign(socket, tree: tree, folder_options: Media.folder_options(tree.roots))
  end

  defp load_items(socket) do
    items =
      Media.list_uploads(
        search: socket.assigns.search,
        sort: socket.assigns.sort,
        folder: folder_scope(socket.assigns.scope, socket.assigns.tree)
      )

    stream(socket, :items, items, reset: true)
  end

  # What `Media.list_uploads(folder:)` expects for each scope.
  defp folder_scope(:all, _tree), do: :all
  defp folder_scope(:unfiled, _tree), do: :root
  defp folder_scope(%Folder{} = folder, tree), do: branch_ids(tree, folder)

  # The folders a scope lists: the chosen one plus its sub-folders, so a folded branch
  # hides nothing. Read off the already-loaded tree for the same reason
  # `Media.folder_options/1` takes loaded roots — re-querying would double the preload on
  # every folder change, upload, edit and drop. A sub-folder has no children (two-level
  # cap); a folder gone between render and click stands for itself alone.
  #
  # The price of reusing the tree: "filter" re-lists against the tree the last load_tree/1
  # left, so a sub-folder another admin created mid-session is missed until the editor
  # clicks anything. Self-healing, and this is a handful of editors, not a busy multi-tenant
  # app — but it is the one place the reuse is observable.
  defp branch_ids(tree, %Folder{parent_id: nil, id: id}) do
    case Enum.find(tree.roots, &(&1.id == id)) do
      %Folder{children: children} -> [id | Enum.map(children, & &1.id)]
      nil -> [id]
    end
  end

  defp branch_ids(_tree, %Folder{id: id}), do: [id]

  # The folder an upload lands in. A sub-folder is a fine home for a file.
  defp folder_scope_id(%Folder{id: id}), do: id
  defp folder_scope_id(_scope), do: nil

  # The parent a new folder is created under — *not* the same question. A sub-folder
  # cannot take children (two-level cap), so creating while standing in one has to go to
  # the top level. Reusing folder_scope_id/1 here handed the sub-folder's id to
  # create_folder/1, which then failed the depth check — while the hint under the form
  # had already promised the top level.
  defp new_folder_parent_id(%Folder{parent_id: nil, id: id}), do: id
  defp new_folder_parent_id(_scope), do: nil

  @impl true
  def handle_event("validate", _params, socket), do: {:noreply, socket}

  def handle_event("filter", %{"search" => search, "sort" => sort}, socket) do
    {:noreply, socket |> assign(search: search, sort: sort) |> load_items()}
  end

  def handle_event("cancel", %{"ref" => ref}, socket) do
    {:noreply, cancel_upload(socket, :files, ref)}
  end

  def handle_event("save", _params, socket) do
    folder_id = folder_scope_id(socket.assigns.scope)

    results =
      consume_uploaded_entries(socket, :files, fn %{path: path}, entry ->
        case Media.store_file(path, %{
               filename: entry.client_name,
               content_type: entry.client_type,
               folder_id: folder_id
             }) do
          {:ok, upload} -> {:ok, {:stored, upload}}
          # Rejected: :image_too_large (pixel bomb) or :unsupported_media_type /
          # other (e.g. spoofed extension, failed magic-byte validation).
          {:error, reason} -> {:ok, {:rejected, reason}}
        end
      end)

    stored = for {:stored, upload} <- results, do: upload
    too_large = Enum.count(results, &(&1 == {:rejected, :image_too_large}))
    rejected = Enum.count(results, &match?({:rejected, r} when r != :image_too_large, &1))

    socket =
      Enum.reduce(stored, socket, fn upload, acc -> stream_insert(acc, :items, upload, at: 0) end)

    {:noreply, socket |> load_tree() |> put_upload_flash(length(stored), rejected, too_large)}
  end

  def handle_event("delete", %{"id" => id}, socket) do
    upload = Media.get_upload!(id)

    case Media.delete_upload(upload) do
      {:ok, _} ->
        {:noreply,
         socket
         |> put_flash(:info, "Datei gelöscht.")
         |> stream_delete(:items, upload)
         |> load_tree()}

      {:error, :in_use} ->
        {:noreply, put_flash(socket, :error, in_use_message(upload))}
    end
  end

  def handle_event("edit", %{"id" => id}, socket) do
    {:noreply, assign(socket, :editing, Media.get_upload!(id))}
  end

  def handle_event("cancel_edit", _params, socket), do: {:noreply, assign(socket, :editing, nil)}

  # `:keep` means the editor stays open on the returned upload — that is how a rotation
  # shows its result and can be repeated (see BbhWeb.Admin.MediaEditor.submit/2).
  def handle_event("save_meta", %{"upload" => _} = params, socket) do
    {action, updated, {kind, message}} = MediaEditor.submit(socket.assigns.editing, params)

    {:noreply,
     socket
     |> assign(:editing, if(action == :keep, do: updated, else: nil))
     |> put_flash(kind, message)
     |> load_tree()
     |> refresh(updated)}
  end

  def handle_event("toggle_new_folder", _params, socket),
    do: {:noreply, assign(socket, :new_folder, not socket.assigns.new_folder)}

  # Sorting is the rare intent and navigating the common one, so the grips are off by
  # default. An unchecked box is absent from a phx-change payload rather than false.
  def handle_event("toggle_edit", params, socket),
    do: {:noreply, assign(socket, :edit_mode, Map.has_key?(params, "edit"))}

  # `expanded` lives for the life of the socket, and this event is reachable by pushEvent
  # and not only from the button the server rendered — so an id that is not a branch is
  # dropped rather than kept forever. That also keeps the ids of deleted folders from
  # collecting in it. Unlike the drop payloads there is nothing to validate the *shape* of:
  # a non-id simply matches no root.
  def handle_event("toggle_folder", %{"id" => id}, socket) do
    expanded = socket.assigns.expanded

    cond do
      MapSet.member?(expanded, id) ->
        {:noreply, assign(socket, :expanded, MapSet.delete(expanded, id))}

      Enum.any?(socket.assigns.tree.roots, &(&1.id == id)) ->
        {:noreply, assign(socket, :expanded, MapSet.put(expanded, id))}

      true ->
        {:noreply, socket}
    end
  end

  def handle_event("create_folder", %{"name" => name}, socket) do
    parent_id = new_folder_parent_id(socket.assigns.scope)

    case Media.create_folder(%{"name" => String.trim(name), "parent_id" => parent_id}) do
      {:ok, _folder} ->
        {:noreply,
         socket
         |> assign(new_folder: false)
         |> load_tree()
         |> put_flash(:info, "Ordner erstellt.")}

      {:error, changeset} ->
        {:noreply, put_flash(socket, :error, folder_error(changeset))}
    end
  end

  def handle_event("delete_folder", _params, socket) do
    case socket.assigns.scope do
      %Folder{} = folder ->
        {:ok, _} = Media.delete_folder(folder)

        target =
          if folder.parent_id,
            do: ~p"/admin/medien?#{[folder: folder.parent_id]}",
            else: ~p"/admin/medien"

        {:noreply,
         socket
         |> put_flash(:info, "Ordner gelöscht. Enthaltene Medien wurden verschoben.")
         |> push_patch(to: target)}

      _ ->
        {:noreply, socket}
    end
  end

  # Dropped a folder onto/between others in the tree, or moved it with Alt+arrow. The
  # ids come from the browser, so everything is re-read and re-validated here; the
  # two-level cap is enforced in Bbh.Media.Folder.move_changeset/4.
  def handle_event("move_folder", %{"id" => id} = params, socket) do
    with %Folder{} = folder <- Media.get_folder(id),
         {:ok, moved} <- Media.move_folder(folder, params["parent_id"], params["position"]) do
      # Unfold the new parent, or the folder just dragged in disappears the moment sorting
      # is switched back off.
      listed = listed_folders(socket)

      {:noreply,
       socket
       |> reveal_parent(moved)
       |> load_tree()
       |> reload_scope()
       |> reload_if_branch_changed(listed)}
    else
      # Gone between the render and the drop — the next tree render is the answer.
      nil -> {:noreply, load_tree(socket)}
      {:error, :not_found} -> {:noreply, load_tree(socket)}
      {:error, changeset} -> {:noreply, put_flash(socket, :error, folder_error(changeset))}
    end
  end

  # Dropped a media tile onto a tree node. An empty folder_id is the "Ohne Ordner" node.
  def handle_event("move_media", %{"id" => id} = params, socket) do
    # Both ids come from the browser, so the tolerant getter — `get_upload!/1` would
    # raise on a non-UUID and take the LiveView with it.
    with %Upload{} = upload <- Media.get_upload(id),
         {:ok, moved} <- Media.move_upload(upload, params["folder_id"]) do
      {:noreply,
       socket
       |> put_flash(:info, moved_message(moved))
       |> load_tree()
       |> refresh(moved)}
    else
      # Deleted between the render and the drop — the next grid render is the answer.
      nil ->
        {:noreply, load_items(socket)}

      {:error, _changeset} ->
        {:noreply, put_flash(socket, :error, "Datei konnte nicht verschoben werden.")}
    end
  end

  # The branch scope gave a folder move reach into the grid, which it never had while a
  # scope was one folder: nesting a folder into the open one pulls its files in and
  # un-nesting takes them away, so the count would claim the new branch while the grid
  # still showed the old set. Only a move across the open branch's boundary can do that
  # though — and a plain sibling reorder is the common case, the whole point of the mode.
  # Comparing the listed ids keeps ten Alt+Downs from being ten full stream resets.
  defp reload_if_branch_changed(socket, listed) do
    if listed_folders(socket) == listed, do: socket, else: load_items(socket)
  end

  # Which folders the grid is drawing from, order-insensitive: reordering a folder's
  # children rewrites the list without changing a single file in it.
  defp listed_folders(socket) do
    case folder_scope(socket.assigns.scope, socket.assigns.tree) do
      ids when is_list(ids) -> Enum.sort(ids)
      scope -> scope
    end
  end

  # A move can change the open folder's own parent, and the assign holds the struct the
  # heading is built from.
  defp reload_scope(socket) do
    case socket.assigns.scope do
      %Folder{id: id} -> assign(socket, :scope, Media.get_folder(id) || :all)
      _ -> socket
    end
  end

  # Keep the grid in step: drop the item if it no longer belongs in the current scope,
  # otherwise re-render it in place. Nothing ever falls out of "Alle Medien".
  defp refresh(socket, updated) do
    if in_scope?(socket.assigns.scope, socket.assigns.tree, updated),
      do: stream_insert(socket, :items, updated),
      else: stream_delete(socket, :items, updated)
  end

  # The predicate half of folder_scope/2, over the same branch_ids/2: a file filed into a
  # sub-folder of the open folder is still listed there, so dropping it from the stream
  # would make it look deleted. No catch-all, like folder_scope/2 — `scope` is closed over
  # three shapes, and a fourth should fail loudly rather than quietly list nothing.
  defp in_scope?(:all, _tree, _upload), do: true
  defp in_scope?(:unfiled, _tree, %{folder_id: folder_id}), do: is_nil(folder_id)

  defp in_scope?(%Folder{} = folder, tree, %{folder_id: folder_id}),
    do: folder_id in branch_ids(tree, folder)

  defp moved_message(%{folder_id: nil}), do: "Datei aus dem Ordner entfernt."

  defp moved_message(%{folder_id: folder_id}) do
    case Media.get_folder(folder_id) do
      %Folder{name: name} -> "Datei nach „#{name}“ verschoben."
      nil -> "Datei verschoben."
    end
  end

  defp in_use_message(upload) do
    places =
      upload
      |> Media.usages()
      |> Enum.map(fn {place, n} -> "#{n}× #{place_label(place)}" end)
      |> Enum.join(", ")

    "„#{upload.filename}“ wird noch verwendet (#{places}) und kann nicht gelöscht werden."
  end

  defp place_label(:articles), do: "Artikel"
  defp place_label(:media_cards), do: "Bild-Karte"
  defp place_label(:galleries), do: "Galerie"

  defp folder_error(changeset) do
    changeset
    |> Ecto.Changeset.traverse_errors(fn {msg, _} -> msg end)
    |> Map.values()
    |> List.flatten()
    |> List.first() || "Ordner konnte nicht gespeichert werden."
  end

  defp put_upload_flash(socket, stored, rejected, too_large) do
    msg = upload_summary(stored, rejected, too_large)

    cond do
      rejected == 0 and too_large == 0 -> put_flash(socket, :info, msg)
      stored == 0 -> put_flash(socket, :error, msg)
      true -> put_flash(socket, :warning, msg)
    end
  end

  defp upload_summary(stored, rejected, too_large) do
    [
      stored > 0 && "#{stored} Datei(en) hochgeladen",
      rejected > 0 && "#{rejected} abgelehnt (kein gültiges Bild/PDF)",
      too_large > 0 && "#{too_large} abgelehnt (Bildauflösung zu hoch)"
    ]
    |> Enum.filter(& &1)
    |> Enum.join(", ")
    |> Kernel.<>(".")
  end

  defp scope_title(:all), do: "Alle Medien"
  defp scope_title(:unfiled), do: "Ohne Ordner"
  defp scope_title(%Folder{parent: %Folder{name: parent}, name: name}), do: "#{parent} / #{name}"
  defp scope_title(%Folder{name: name}), do: name

  # Same folder, same wording as the heading above the grid — a sub-folder's bare name
  # is ambiguous when two parents both hold a "2026".
  defp upload_target(%Folder{} = folder), do: " · Ziel: #{scope_title(folder)}"
  defp upload_target(_scope), do: ""

  defp new_folder_hint(%Folder{parent_id: nil, name: name}), do: "Neuer Unterordner in #{name}"
  defp new_folder_hint(_scope), do: "Neuer Ordner auf oberster Ebene"

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.admin flash={@flash} current_scope={@current_scope} active={:media}>
      <.header>
        Medien
        <:subtitle>Bilder und PDFs hochladen, in Ordnern verwalten.</:subtitle>
      </.header>

      <form id="upload-form" phx-submit="save" phx-change="validate" class="mt-4">
        <div
          class="rounded-box border-2 border-dashed border-base-300 p-6 text-center"
          phx-drop-target={@uploads.files.ref}
        >
          <.live_file_input upload={@uploads.files} class="file-input file-input-bordered" />
          <p class="mt-2 text-sm text-base-content/60">
            JPG, PNG, WebP, GIF oder PDF · bis 20&nbsp;MB · max. 10 Dateien{upload_target(@scope)}
          </p>
        </div>

        <div :if={@uploads.files.entries != []} class="mt-4 space-y-2">
          <div
            :for={entry <- @uploads.files.entries}
            class="flex items-center gap-3 rounded-box border border-base-300 p-2"
          >
            <.live_img_preview
              :if={String.starts_with?(entry.client_type, "image/")}
              entry={entry}
              class="size-14 rounded object-cover"
            />
            <span
              :if={not String.starts_with?(entry.client_type, "image/")}
              class="flex size-14 items-center justify-center rounded bg-base-200"
            >
              <.icon name="hero-document" class="size-7 text-base-content/60" />
            </span>
            <div class="flex-1">
              <p class="truncate text-sm">{entry.client_name}</p>
              <progress class="progress progress-primary w-full" value={entry.progress} max="100" />
            </div>
            <button
              type="button"
              phx-click="cancel"
              phx-value-ref={entry.ref}
              class="btn btn-ghost btn-sm"
              aria-label="Abbrechen"
            >
              ✕
            </button>
          </div>
          <p :for={err <- upload_errors(@uploads.files)} class="text-sm text-error">
            {upload_error_label(err)}
          </p>
          <.button variant="primary" phx-disable-with="Lädt hoch…">Hochladen</.button>
        </div>
      </form>

      <div class="mt-8 flex flex-wrap items-center justify-between gap-2">
        <h2 class="text-lg font-semibold">Ordner</h2>
        <div class="flex items-center gap-3">
          <%!-- phx-submit as well as phx-change: a checkbox does not block implicit
                submission, so without it Enter on the box would be a real browser form
                submit — a GET to /admin/medien?edit=on, which remounts the LiveView and
                drops both the mode and the open folder. Same reason as the picker's
                search box (BbhWeb.Admin.MediaPicker). --%>
          <form phx-change="toggle_edit" phx-submit="toggle_edit" id="tree-edit-mode">
            <label class="flex cursor-pointer items-center gap-2 text-sm">
              <input type="checkbox" name="edit" checked={@edit_mode} class="checkbox checkbox-sm" />
              Ordner sortieren
            </label>
          </form>
          <button type="button" phx-click="toggle_new_folder" class="btn btn-outline btn-sm">
            <.icon name="hero-folder-plus" class="size-4" /> Neuer Ordner
          </button>
        </div>
      </div>

      <form
        :if={@new_folder}
        id="new-folder-form"
        phx-submit="create_folder"
        class="mt-2 flex flex-wrap items-end gap-2"
      >
        <input
          type="text"
          name="name"
          placeholder="Ordnername"
          required
          maxlength="120"
          autofocus
          class="input input-bordered"
        />
        <.button variant="primary">Anlegen</.button>
        <span class="text-sm text-base-content/60">{new_folder_hint(@scope)}</span>
      </form>

      <%!-- Fully expanded exactly while sorting is on, because that is when a folded
            branch would be somewhere a dragged file lands by accident. With the grips
            gone nothing can be dropped between rows, so branches fold — the tree grows
            by one row per archive year and would otherwise push the grid off screen.

            A nested <ul> of links, deliberately *not* role="tree". A real tree widget
            promises roaming arrow-key navigation and a roving tabindex; this offers
            plain links plus Alt+arrows for reordering. Announcing "tree" and not
            honouring the interaction contract would leave screen-reader users worse
            off than the nesting alone does. --%>
      <nav
        id="media-tree"
        phx-hook="MediaTree"
        data-edit-mode={to_string(@edit_mode)}
        aria-label="Ordner"
        aria-describedby={@edit_mode && "tree-keys"}
        class="mt-3"
      >
        <%!-- The grip is decorative and unfocusable, so without this the keyboard route
              is undiscoverable — and it is the only one that does not need a mouse. Only
              while sorting is on: that is when the keys do anything. --%>
        <p :if={@edit_mode} id="tree-keys" class="sr-only">
          Alt und Pfeil hoch oder runter sortiert einen Ordner, Alt und Pfeil rechts
          verschachtelt ihn unter dem Ordner darüber, Alt und Pfeil links löst ihn wieder heraus.
        </p>
        <ul class="space-y-0.5">
          <li>
            <.tree_row
              patch={~p"/admin/medien"}
              icon="hero-square-3-stack-3d"
              label="Alle Medien"
              count={@tree.total}
              selected={@scope == :all}
            />
          </li>
          <li>
            <.tree_row
              patch={~p"/admin/medien?#{[folder: "none"]}"}
              icon="hero-inbox"
              label="Ohne Ordner"
              count={@tree.unfiled}
              selected={@scope == :unfiled}
              accepts="media"
            />
          </li>
          <.tree_branch
            :for={root <- @tree.roots}
            root={root}
            counts={@tree.counts}
            scope={@scope}
            edit_mode={@edit_mode}
            expanded={MapSet.member?(@expanded, root.id)}
          />
        </ul>
        <p :if={@tree.roots == []} class="mt-2 text-sm text-base-content/50">
          Noch keine Ordner.
        </p>
      </nav>

      <div class="mt-8 flex flex-wrap items-center justify-between gap-2">
        <h2 class="text-lg font-semibold">{scope_title(@scope)}</h2>
        <button
          :if={match?(%Folder{}, @scope)}
          type="button"
          phx-click="delete_folder"
          data-confirm={"Ordner „#{@scope.name}“ löschen? Enthaltene Medien werden nach oben verschoben."}
          class="btn btn-ghost btn-xs text-error"
        >
          <.icon name="hero-trash" class="size-4" /> Ordner löschen
        </button>
      </div>

      <form phx-change="filter" id="media-filter" class="mt-2 flex flex-wrap items-end gap-3">
        <label class="fieldset">
          <span class="label mb-1">Suche</span>
          <input
            type="text"
            name="search"
            value={@search}
            placeholder="Dateiname oder Titel"
            phx-debounce="300"
            class="input input-bordered"
          />
        </label>
        <label class="fieldset">
          <span class="label mb-1">Sortierung</span>
          <select name="sort" class="select select-bordered">
            <option value="newest" selected={@sort == "newest"}>Neueste zuerst</option>
            <option value="oldest" selected={@sort == "oldest"}>Älteste zuerst</option>
            <option value="name" selected={@sort == "name"}>Name (A–Z)</option>
          </select>
        </label>
      </form>

      <div
        id="media-grid"
        phx-hook="MediaGrid"
        phx-update="stream"
        class="mt-4 grid grid-cols-2 gap-4 sm:grid-cols-3 md:grid-cols-4"
      >
        <figure
          :for={{dom_id, item} <- @streams.items}
          id={dom_id}
          data-media-id={item.id}
          draggable="true"
          class="rounded-box border border-base-300 p-2"
        >
          <img
            :if={Media.image?(item)}
            src={media_url(item, width: 300, height: 300)}
            alt=""
            draggable="false"
            class="aspect-square w-full rounded object-cover"
          />
          <a
            :if={not Media.image?(item)}
            href={media_url(item)}
            target="_blank"
            draggable="false"
            class="flex aspect-square w-full flex-col items-center justify-center rounded bg-base-200"
          >
            <.icon name="hero-document-text" class="size-10 text-base-content/60" />
            <span class="mt-1 text-xs text-base-content/60">PDF</span>
          </a>
          <figcaption class="mt-1 space-y-1">
            <span class="block truncate text-xs" title={item.filename}>
              {item.title || item.filename}
            </span>
            <div class="flex items-center justify-between gap-1">
              <button
                type="button"
                phx-click="edit"
                phx-value-id={item.id}
                class="link link-primary text-xs"
              >
                Bearbeiten
              </button>
              <.link
                phx-click={JS.push("delete", value: %{id: item.id})}
                data-confirm="Diese Datei wirklich löschen?"
                class="link link-error text-xs"
                title="Löschen"
                aria-label="Löschen"
              >
                <.icon name="hero-trash" class="size-4" />
              </.link>
            </div>
          </figcaption>
        </figure>
      </div>

      <.media_editor :if={@editing} upload={@editing} folder_options={@folder_options} />
    </Layouts.admin>
    """
  end

  defp selected?(%Folder{id: id}, %Folder{id: id}), do: true
  defp selected?(_scope, _folder), do: false

  attr :root, Folder, required: true
  attr :counts, :map, required: true
  attr :scope, :any, required: true
  attr :edit_mode, :boolean, required: true
  attr :expanded, :boolean, required: true

  # One top-level folder and the sub-folders under it. A component rather than two nested
  # loops in render/1 so the four facts about a branch — does it have children, is it
  # folded, is it visible, can it be dragged — are each stated once. Spelled inline they
  # were restated five times, with the list's `hidden` negating the row's `expanded`:
  # exactly the shape where a later edit updates one and not the other.
  defp tree_branch(assigns) do
    ~H"""
    <li class="pt-0.5">
      <.tree_row
        patch={~p"/admin/medien?#{[folder: @root.id]}"}
        icon="hero-folder"
        label={@root.name}
        count={Map.get(@counts, @root.id, 0)}
        selected={selected?(@scope, @root)}
        accepts="folder media"
        folder_id={@root.id}
        parent_id=""
        leaf={@root.children == []}
        draggable={@edit_mode}
        expanded={@expanded}
      />
      <%!-- Folded with `hidden`, not `:if`: the list keeps existing, so the toggle's
            aria-controls always resolves and folding is an attribute patch rather than a
            structural one. `[hidden]` is display:none, so a folded row is no drop target
            either — and in edit mode nothing is folded, which is what keeps the hook's
            siblings() measuring a fully visible level. --%>
      <ul
        :if={@root.children != []}
        id={"subfolders-#{@root.id}"}
        data-subfolders
        hidden={not (@edit_mode or @expanded)}
        class="ml-5 space-y-0.5 border-l border-base-300 pl-2"
      >
        <li :for={child <- @root.children}>
          <.tree_row
            patch={~p"/admin/medien?#{[folder: child.id]}"}
            icon="hero-folder"
            label={child.name}
            count={Map.get(@counts, child.id, 0)}
            selected={selected?(@scope, child)}
            accepts="folder media"
            folder_id={child.id}
            parent_id={@root.id}
            draggable={@edit_mode}
          />
        </li>
      </ul>
    </li>
    """
  end

  attr :patch, :string, required: true
  attr :icon, :string, required: true
  attr :label, :string, required: true
  attr :count, :integer, required: true
  attr :selected, :boolean, required: true
  # What the row accepts on drop, read by the MediaTree hook: "folder media", "media",
  # or nothing at all ("Alle Medien" is a view, not a destination).
  attr :accepts, :string, default: ""
  attr :folder_id, :string, default: nil
  attr :parent_id, :string, default: nil
  # A folder with sub-folders cannot be nested (two-level cap), so the hook refuses to
  # offer "drop into" for it instead of letting the server reject the move afterwards.
  attr :leaf, :boolean, default: true
  # One slot in front of the label, three states: the grip while sorting, otherwise the
  # fold toggle if there is a branch to fold, otherwise a spacer keeping the rows aligned.
  attr :draggable, :boolean, default: false
  attr :expanded, :boolean, default: false

  defp tree_row(assigns) do
    # Derived, not passed: the grip and the toggle share one slot, so a caller able to ask
    # for both could render two and lose the spacer that keeps the level aligned.
    assigns = assign(assigns, :expandable, not assigns.draggable and not assigns.leaf)

    ~H"""
    <div
      data-node
      data-accepts={@accepts}
      data-folder-id={@folder_id}
      data-parent-id={@parent_id}
      data-leaf={to_string(@leaf)}
      class={[
        "group relative flex items-center gap-1 rounded px-1 py-1",
        @selected && "bg-base-200 font-semibold"
      ]}
    >
      <%!-- The grip is a separate element on purpose: dragging and clicking would
            otherwise compete on the same link, and a half-started drag navigates. --%>
      <span
        :if={@draggable}
        data-drag-handle
        draggable="true"
        aria-hidden="true"
        class="cursor-grab text-base-content/30 group-hover:text-base-content/60"
      >
        <.icon name="hero-bars-2" class="size-4" />
      </span>
      <%!-- The icon alone is 16px, under WCAG 2.5.8's 24px minimum, and it sits directly
            left of the row's link — a near-miss would navigate instead of folding. The
            padding buys the target back, the negative margin keeps the row's height. --%>
      <button
        :if={@expandable}
        type="button"
        phx-click="toggle_folder"
        phx-value-id={@folder_id}
        aria-expanded={to_string(@expanded)}
        aria-controls={"subfolders-#{@folder_id}"}
        aria-label={"Unterordner von „#{@label}“ #{if @expanded, do: "ausblenden", else: "anzeigen"}"}
        class="-m-1 cursor-pointer p-1 text-base-content/40 hover:text-base-content"
      >
        <.icon
          name={if @expanded, do: "hero-chevron-down", else: "hero-chevron-right"}
          class="size-4"
        />
      </button>
      <span :if={not @draggable and not @expandable} class="size-4" aria-hidden="true"></span>
      <%!-- A stable id keeps morphdom matching this link to *this* folder across the
            patch that follows a move. Without it the DOM node is matched positionally,
            so focus stays on the slot rather than the folder — and a second Alt+Up
            would move whichever folder had slid into that position. --%>
      <.link
        id={@folder_id && "tree-node-#{@folder_id}"}
        patch={@patch}
        data-tree-link
        aria-current={@selected && "page"}
        draggable="false"
        class="flex grow items-center gap-2 truncate py-0.5 text-sm hover:underline"
      >
        <.icon name={@icon} class="size-4 shrink-0 text-primary" />
        <span class="truncate">{@label}</span>
      </.link>
      <span data-count={@count} class="shrink-0 text-xs tabular-nums text-base-content/50">
        {@count}
      </span>
    </div>
    """
  end

  defp upload_error_label(:too_large), do: "Datei ist zu groß (max. 20 MB)."
  defp upload_error_label(:too_many_files), do: "Zu viele Dateien (max. 10)."
  defp upload_error_label(:not_accepted), do: "Dateityp nicht erlaubt."
  defp upload_error_label(_), do: "Fehler beim Hochladen."
end
