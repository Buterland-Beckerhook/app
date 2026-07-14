defmodule BbhWeb.Admin.MediaLive.Index do
  use BbhWeb, :live_view

  alias Bbh.Media

  @impl true
  def mount(_params, _session, socket) do
    socket =
      socket
      |> assign(page_title: "Medien", search: "", sort: "newest")
      |> assign(items: Media.list_uploads())
      |> allow_upload(:files,
        accept: ~w(.jpg .jpeg .png .webp .gif),
        max_entries: 10,
        max_file_size: 20_000_000
      )

    {:ok, socket}
  end

  @impl true
  def handle_event("validate", _params, socket), do: {:noreply, socket}

  def handle_event("filter", %{"search" => search, "sort" => sort}, socket) do
    {:noreply,
     socket
     |> assign(search: search, sort: sort)
     |> assign(items: Media.list_uploads(search: search, sort: sort))}
  end

  def handle_event("cancel", %{"ref" => ref}, socket) do
    {:noreply, cancel_upload(socket, :files, ref)}
  end

  def handle_event("save", _params, socket) do
    consume_uploaded_entries(socket, :files, fn %{path: path}, entry ->
      {:ok, _upload} =
        Media.store_file(path, %{filename: entry.client_name, content_type: entry.client_type})

      {:ok, entry.uuid}
    end)

    {:noreply, socket |> put_flash(:info, "Bilder hochgeladen.") |> reload_items()}
  end

  def handle_event("delete", %{"id" => id}, socket) do
    id |> Media.get_upload!() |> Media.delete_upload()

    {:noreply, socket |> put_flash(:info, "Bild gelöscht.") |> reload_items()}
  end

  defp reload_items(socket),
    do:
      assign(
        socket,
        :items,
        Media.list_uploads(search: socket.assigns.search, sort: socket.assigns.sort)
      )

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.admin flash={@flash} current_scope={@current_scope} active={:media}>
      <.header>
        Medien
        <:subtitle>Bilder hochladen und verwalten.</:subtitle>
      </.header>

      <form id="upload-form" phx-submit="save" phx-change="validate" class="mt-6">
        <div
          class="rounded-box border-2 border-dashed border-base-300 p-6 text-center"
          phx-drop-target={@uploads.files.ref}
        >
          <.live_file_input upload={@uploads.files} class="file-input file-input-bordered" />
          <p class="mt-2 text-sm text-base-content/60">
            JPG, PNG, WebP oder GIF · bis 20&nbsp;MB · max. 10 Dateien
          </p>
        </div>

        <div :if={@uploads.files.entries != []} class="mt-4 space-y-2">
          <div
            :for={entry <- @uploads.files.entries}
            class="flex items-center gap-3 rounded-box border border-base-300 p-2"
          >
            <.live_img_preview entry={entry} class="size-14 rounded object-cover" />
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

      <form phx-change="filter" class="mt-8 flex flex-wrap items-end gap-3">
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

      <div class="mt-4 grid grid-cols-2 gap-4 sm:grid-cols-3 md:grid-cols-4">
        <figure :for={item <- @items} class="rounded-box border border-base-300 p-2">
          <img
            src={media_url(item, width: 300, height: 300)}
            alt={item.title || item.filename}
            class="aspect-square w-full rounded object-cover"
          />
          <figcaption class="mt-1 flex items-center justify-between gap-1">
            <span class="truncate text-xs" title={item.filename}>{item.filename}</span>
            <.link
              phx-click={JS.push("delete", value: %{id: item.id})}
              data-confirm="Dieses Bild wirklich löschen?"
              class="link link-error text-xs"
              title="Löschen"
              aria-label="Löschen"
            >
              <.icon name="hero-trash" class="size-4" />
            </.link>
          </figcaption>
        </figure>
      </div>
    </Layouts.admin>
    """
  end

  defp upload_error_label(:too_large), do: "Datei ist zu groß (max. 20 MB)."
  defp upload_error_label(:too_many_files), do: "Zu viele Dateien (max. 10)."
  defp upload_error_label(:not_accepted), do: "Dateityp nicht erlaubt."
  defp upload_error_label(_), do: "Fehler beim Hochladen."
end
