defmodule BbhWeb.Admin.MediaLive.Index do
  use BbhWeb, :live_view

  alias Bbh.Media
  alias Bbh.Media.Folder

  @impl true
  def mount(_params, _session, socket) do
    socket =
      socket
      |> assign(page_title: "Medien", search: "", sort: "newest")
      |> assign(folder: nil, editing: nil, new_folder: false)
      |> allow_upload(:files,
        accept: ~w(.jpg .jpeg .png .webp .gif .pdf),
        max_entries: 10,
        max_file_size: 20_000_000
      )

    {:ok, socket}
  end

  @impl true
  def handle_params(params, _uri, socket) do
    folder = Media.get_folder(params["folder"])

    {:noreply,
     socket
     |> assign(folder: folder, editing: nil, new_folder: false)
     |> assign(subfolders: subfolders_for(folder))
     |> assign(folder_options: folder_options())
     |> load_items()}
  end

  # A folder shows its own sub-folders; the root shows all top-level folders.
  defp subfolders_for(nil), do: Media.list_subfolders(nil)
  defp subfolders_for(%Folder{parent_id: nil, id: id}), do: Media.list_subfolders(id)
  defp subfolders_for(%Folder{}), do: []

  defp load_items(socket) do
    items =
      Media.list_uploads(
        search: socket.assigns.search,
        sort: socket.assigns.sort,
        folder: folder_scope(socket.assigns.folder)
      )

    stream(socket, :items, items, reset: true)
  end

  defp folder_scope(nil), do: :root
  defp folder_scope(%Folder{id: id}), do: id

  @impl true
  def handle_event("validate", _params, socket), do: {:noreply, socket}

  def handle_event("filter", %{"search" => search, "sort" => sort}, socket) do
    {:noreply, socket |> assign(search: search, sort: sort) |> load_items()}
  end

  def handle_event("cancel", %{"ref" => ref}, socket) do
    {:noreply, cancel_upload(socket, :files, ref)}
  end

  def handle_event("save", _params, socket) do
    folder_id = folder_scope_id(socket.assigns.folder)

    results =
      consume_uploaded_entries(socket, :files, fn %{path: path}, entry ->
        case Media.store_file(path, %{
               filename: entry.client_name,
               content_type: entry.client_type,
               folder_id: folder_id
             }) do
          {:ok, upload} -> {:ok, {:stored, upload}}
          # Magic-byte validation rejected the file (e.g. spoofed extension).
          {:error, _reason} -> {:ok, :rejected}
        end
      end)

    stored = for {:stored, upload} <- results, do: upload
    rejected = Enum.count(results, &(&1 == :rejected))

    socket =
      Enum.reduce(stored, socket, fn upload, acc -> stream_insert(acc, :items, upload, at: 0) end)

    {:noreply, put_upload_flash(socket, length(stored), rejected)}
  end

  def handle_event("delete", %{"id" => id}, socket) do
    upload = Media.get_upload!(id)

    case Media.delete_upload(upload) do
      {:ok, _} ->
        {:noreply, socket |> put_flash(:info, "Datei gelöscht.") |> stream_delete(:items, upload)}

      {:error, :in_use} ->
        {:noreply, put_flash(socket, :error, in_use_message(upload))}
    end
  end

  def handle_event("edit", %{"id" => id}, socket) do
    {:noreply, assign(socket, :editing, Media.get_upload!(id))}
  end

  def handle_event("cancel_edit", _params, socket), do: {:noreply, assign(socket, :editing, nil)}

  def handle_event("save_meta", %{"upload" => params}, socket) do
    upload = socket.assigns.editing
    params = Map.update(params, "folder_id", nil, &blank_to_nil/1)

    case Media.update_upload(upload, params) do
      {:ok, updated} ->
        socket = socket |> assign(editing: nil) |> put_flash(:info, "Gespeichert.")

        # If it moved out of the folder currently shown, drop it from the grid.
        if updated.folder_id == folder_scope_id(socket.assigns.folder) do
          {:noreply, stream_insert(socket, :items, updated)}
        else
          {:noreply, stream_delete(socket, :items, updated)}
        end

      {:error, _changeset} ->
        {:noreply, put_flash(socket, :error, "Konnte nicht gespeichert werden.")}
    end
  end

  def handle_event("toggle_new_folder", _params, socket),
    do: {:noreply, assign(socket, :new_folder, not socket.assigns.new_folder)}

  def handle_event("create_folder", %{"name" => name}, socket) do
    parent_id = folder_scope_id(socket.assigns.folder)

    case Media.create_folder(%{"name" => String.trim(name), "parent_id" => parent_id}) do
      {:ok, _folder} ->
        {:noreply,
         socket
         |> assign(new_folder: false, subfolders: subfolders_for(socket.assigns.folder))
         |> assign(folder_options: folder_options())
         |> put_flash(:info, "Ordner erstellt.")}

      {:error, changeset} ->
        {:noreply, put_flash(socket, :error, folder_error(changeset))}
    end
  end

  def handle_event("delete_folder", _params, socket) do
    case socket.assigns.folder do
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

  defp folder_scope_id(nil), do: nil
  defp folder_scope_id(%Folder{id: id}), do: id

  defp blank_to_nil(""), do: nil
  defp blank_to_nil(v), do: v

  # A flat, indented option list of all folders (plus "no folder") for the move select.
  defp folder_options do
    roots = Media.list_root_folders()

    [{"— Kein Ordner —", ""}] ++
      Enum.flat_map(roots, fn root ->
        [{root.name, root.id}] ++
          Enum.map(root.children, fn child -> {"#{root.name} / #{child.name}", child.id} end)
      end)
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
    |> List.first() || "Ordner konnte nicht erstellt werden."
  end

  defp put_upload_flash(socket, stored, 0),
    do: put_flash(socket, :info, "#{stored} Datei(en) hochgeladen.")

  defp put_upload_flash(socket, 0, _rejected),
    do: put_flash(socket, :error, "Datei wurde nicht als gültiges Bild/PDF erkannt.")

  defp put_upload_flash(socket, stored, rejected),
    do:
      put_flash(
        socket,
        :warning,
        "#{stored} hochgeladen, #{rejected} abgelehnt (kein gültiges Bild/PDF)."
      )

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.admin flash={@flash} current_scope={@current_scope} active={:media}>
      <.header>
        Medien
        <:subtitle>Bilder und PDFs hochladen, in Ordnern verwalten.</:subtitle>
      </.header>

      <nav class="mt-4 flex flex-wrap items-center gap-1 text-sm" aria-label="Ordnerpfad">
        <.link patch={~p"/admin/medien"} class={["link", is_nil(@folder) && "font-semibold"]}>
          Alle Medien
        </.link>
        <span :if={@folder && @folder.parent} class="text-base-content/40">/</span>
        <.link
          :if={@folder && @folder.parent}
          patch={~p"/admin/medien?#{[folder: @folder.parent.id]}"}
          class="link"
        >
          {@folder.parent.name}
        </.link>
        <span :if={@folder} class="text-base-content/40">/</span>
        <span :if={@folder} class="font-semibold">{@folder.name}</span>

        <button
          :if={@folder}
          type="button"
          phx-click="delete_folder"
          data-confirm={"Ordner „#{@folder.name}“ löschen? Enthaltene Medien werden nach oben verschoben."}
          class="btn btn-ghost btn-xs ml-2 text-error"
        >
          <.icon name="hero-trash" class="size-4" /> Ordner löschen
        </button>
      </nav>

      <form id="upload-form" phx-submit="save" phx-change="validate" class="mt-4">
        <div
          class="rounded-box border-2 border-dashed border-base-300 p-6 text-center"
          phx-drop-target={@uploads.files.ref}
        >
          <.live_file_input upload={@uploads.files} class="file-input file-input-bordered" />
          <p class="mt-2 text-sm text-base-content/60">
            JPG, PNG, WebP, GIF oder PDF · bis 20&nbsp;MB · max. 10 Dateien{if @folder,
              do: " · Ziel: #{@folder.name}"}
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

      <div class="mt-8 flex items-center justify-between gap-2">
        <h2 class="text-lg font-semibold">Ordner</h2>
        <button type="button" phx-click="toggle_new_folder" class="btn btn-outline btn-sm">
          <.icon name="hero-folder-plus" class="size-4" /> Neuer Ordner
        </button>
      </div>

      <form
        :if={@new_folder}
        id="new-folder-form"
        phx-submit="create_folder"
        class="mt-2 flex items-end gap-2"
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
      </form>

      <div :if={@subfolders != []} class="mt-3 flex flex-wrap gap-2">
        <.link
          :for={sf <- @subfolders}
          patch={~p"/admin/medien?#{[folder: sf.id]}"}
          class="flex items-center gap-2 rounded-box border border-base-300 px-3 py-2 hover:bg-base-200"
        >
          <.icon name="hero-folder" class="size-5 text-primary" />
          <span class="text-sm">{sf.name}</span>
        </.link>
      </div>
      <p :if={@subfolders == [] and is_nil(@folder)} class="mt-2 text-sm text-base-content/50">
        Noch keine Ordner.
      </p>

      <form phx-change="filter" id="media-filter" class="mt-8 flex flex-wrap items-end gap-3">
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
        phx-update="stream"
        class="mt-4 grid grid-cols-2 gap-4 sm:grid-cols-3 md:grid-cols-4"
      >
        <figure
          :for={{dom_id, item} <- @streams.items}
          id={dom_id}
          class="rounded-box border border-base-300 p-2"
        >
          <img
            :if={Media.image?(item)}
            src={media_url(item, width: 300, height: 300)}
            alt={item.title || item.filename}
            class="aspect-square w-full rounded object-cover"
          />
          <a
            :if={not Media.image?(item)}
            href={media_url(item)}
            target="_blank"
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

  # Modal editor for a single media item's metadata and folder.
  attr :upload, :map, required: true
  attr :folder_options, :list, required: true

  defp media_editor(assigns) do
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
          <img
            :if={Media.image?(@upload)}
            src={media_url(@upload, width: 120, height: 120)}
            alt=""
            class="size-16 rounded object-cover"
          />
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

  defp upload_error_label(:too_large), do: "Datei ist zu groß (max. 20 MB)."
  defp upload_error_label(:too_many_files), do: "Zu viele Dateien (max. 10)."
  defp upload_error_label(:not_accepted), do: "Dateityp nicht erlaubt."
  defp upload_error_label(_), do: "Fehler beim Hochladen."
end
