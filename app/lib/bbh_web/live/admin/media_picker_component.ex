defmodule BbhWeb.Admin.MediaPickerComponent do
  @moduledoc """
  A shared modal for inserting a library file into a Trix editor.

  Mount it once per form page that has rich-text fields:

      <.live_component module={BbhWeb.Admin.MediaPickerComponent} id="media-picker" />

  The `TrixEditor` JS hook adds a toolbar button that opens this modal via
  `pushEventTo("#media-picker", "open", {editor: <wrapper id>})`. Picking a file pushes a
  `"media_picker:insert"` event back to the client with the target editor id and the HTML
  to insert — an `<img>` for images, otherwise a download `<a>` link.
  """
  use BbhWeb, :live_component

  alias Bbh.Media

  @impl true
  def update(assigns, socket) do
    {:ok,
     socket
     |> assign(assigns)
     |> assign_new(:open, fn -> false end)
     |> assign_new(:q, fn -> "" end)
     |> assign_new(:editor, fn -> nil end)
     |> assign_new(:files, fn -> [] end)}
  end

  @impl true
  def handle_event("open", %{"editor" => editor}, socket) do
    {:noreply, assign(socket, open: true, editor: editor, q: "", files: Media.list_uploads())}
  end

  def handle_event("search", %{"q" => q}, socket) do
    {:noreply, assign(socket, q: q, files: Media.list_uploads(search: q))}
  end

  def handle_event("close", _params, socket) do
    {:noreply, assign(socket, open: false)}
  end

  def handle_event("select", %{"id" => id}, socket) do
    upload = Media.get_upload!(id)

    {:noreply,
     socket
     |> assign(open: false)
     |> push_event("media_picker:insert", %{
       editor: socket.assigns.editor,
       html: insert_html(upload)
     })}
  end

  @doc "The snippet Trix inserts: an `<img>` for images, else a labelled download `<a>` link."
  def insert_html(upload) do
    url = media_url(upload)
    label = upload.title || upload.filename

    if Media.image?(upload) do
      ~s(<img src="#{url}" alt="#{esc(label)}">)
    else
      ~s(<a href="#{url}">#{esc(label)}</a>)
    end
  end

  defp esc(value), do: value |> to_string() |> Plug.HTML.html_escape()

  @impl true
  def render(assigns) do
    ~H"""
    <div id={@id}>
      <div
        :if={@open}
        class="fixed inset-0 z-50 flex items-center justify-center bg-black/50 p-4"
        phx-window-keydown="close"
        phx-key="Escape"
        phx-target={@myself}
      >
        <div
          class="max-h-[85vh] w-full max-w-3xl overflow-hidden rounded-lg bg-base-100 shadow-xl"
          phx-click-away="close"
          phx-target={@myself}
        >
          <div class="flex items-center justify-between border-b border-base-300 p-4">
            <h2 class="text-lg font-semibold">Aus Mediathek einfügen</h2>
            <button type="button" phx-click="close" phx-target={@myself} aria-label="Schließen">
              <.icon name="hero-x-mark" class="size-5" />
            </button>
          </div>

          <div class="p-4">
            <form phx-change="search" phx-target={@myself} class="mb-4">
              <label class="input input-bordered flex items-center gap-2">
                <.icon name="hero-magnifying-glass" class="size-4 opacity-60" />
                <input
                  type="search"
                  name="q"
                  value={@q}
                  placeholder="Dateien suchen…"
                  phx-debounce="200"
                  autocomplete="off"
                  class="grow"
                />
              </label>
            </form>

            <div class="max-h-[55vh] grid grid-cols-2 gap-3 overflow-y-auto sm:grid-cols-3 md:grid-cols-4">
              <button
                :for={u <- @files}
                type="button"
                phx-click="select"
                phx-value-id={u.id}
                phx-target={@myself}
                class="group flex flex-col overflow-hidden rounded border border-base-300 text-left hover:border-primary"
              >
                <div class="flex aspect-square items-center justify-center bg-base-200">
                  <img
                    :if={Media.image?(u)}
                    src={media_url(u, width: 200, height: 200)}
                    alt={u.title || u.filename}
                    loading="lazy"
                    class="h-full w-full object-cover"
                  />
                  <.icon :if={!Media.image?(u)} name="hero-document" class="size-10 opacity-50" />
                </div>
                <span class="truncate p-1.5 text-xs">{u.title || u.filename}</span>
              </button>
            </div>

            <p :if={@files == []} class="py-8 text-center text-sm text-base-content/60">
              Keine Dateien gefunden.
            </p>
          </div>
        </div>
      </div>
    </div>
    """
  end
end
