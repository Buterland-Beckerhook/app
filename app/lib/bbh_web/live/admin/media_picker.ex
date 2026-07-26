defmodule BbhWeb.Admin.MediaPicker do
  @moduledoc """
  One modal for picking a file from the media library — folder path, sub-folders, search
  and grid — shared by everything that inserts media: an article's images, the page
  blocks (Bild-Karte, Galerie) and the Trix toolbar.

  Browsing is folder-scoped, so a picture can be found by where it was filed instead of
  by remembering its name. Searching deliberately spans *all* folders, so an unfiled or
  misfiled picture is still reachable.

  Mount it once per form page:

      <.live_component module={BbhWeb.Admin.MediaPicker} id="media-picker" />

  Open it from the host with a plain button, passing along whatever the host needs to
  route the choice back:

      <button phx-click="open" phx-target="#media-picker" phx-value-context="article_image">

  Picking a file sends `{:media_selected, params, media_id}` to the host LiveView, where
  `params` is exactly the `phx-value-*` map the modal was opened with — so a host with
  several pickable slots can tell them apart (see the `pb_id` the page form passes).

  > #### Host contract {: .warning}
  >
  > A host must handle **every** context it renders a button for, or none at all (the
  > Trix-only case, where the reply never leaves this component). An unmatched
  > `handle_info/2` clause takes the whole LiveView down, and nothing checks a
  > `phx-value-context` string against the host's patterns at compile time — so each form
  > that renders picker buttons has a test that opens every one of them and picks
  > (`page_live_test.exs`, `media_picker_test.exs`).

  The Trix case is handled in here: its toolbar button is added by the `TrixEditor` JS
  hook, which opens the modal with the editor's DOM id, and the reply is a `push_event`
  back to that hook rather than something the host cares about.
  """
  use BbhWeb, :live_component

  alias Bbh.Media
  alias Bbh.Media.Folder

  @impl true
  def update(assigns, socket) do
    {:ok,
     socket
     |> assign(assigns)
     |> assign_new(:open, fn -> false end)
     |> assign_new(:params, fn -> %{} end)
     |> assign_new(:folder, fn -> nil end)
     |> assign_new(:search, fn -> "" end)
     |> assign_new(:files, fn -> [] end)
     |> assign_new(:subfolders, fn -> [] end)}
  end

  @impl true
  def handle_event("open", params, socket) do
    {:noreply,
     socket
     |> assign(open: true, params: params, folder: nil, search: "")
     |> load()}
  end

  def handle_event("close", _params, socket), do: {:noreply, assign(socket, :open, false)}

  def handle_event("browse", %{"folder_id" => folder_id}, socket) do
    {:noreply,
     socket
     |> assign(folder: Media.get_folder(blank_to_nil(folder_id)), search: "")
     |> load()}
  end

  def handle_event("search", %{"search" => search}, socket) do
    {:noreply, socket |> assign(:search, search) |> load()}
  end

  def handle_event("select", %{"id" => id}, socket) do
    %{params: params} = socket.assigns

    socket =
      case params do
        # Trix: reply straight to the editor hook that opened us.
        %{"editor" => editor} ->
          push_event(socket, "media_picker:insert", %{
            editor: editor,
            html: insert_html(Media.get_upload!(id))
          })

        _ ->
          send(self(), {:media_selected, params, id})
          socket
      end

    {:noreply, assign(socket, :open, keep_open?(params))}
  end

  # Slots that usually take several pictures in a row (an article's images, a gallery)
  # keep the modal open; a single-image slot is done after one pick.
  defp keep_open?(%{"context" => context}), do: context in ~w(article_image gallery)
  defp keep_open?(_params), do: false

  # Only Trix can make use of a non-image (it inserts a download link for it).
  defp images_only?(%{"editor" => _}), do: false
  defp images_only?(_params), do: true

  defp load(socket) do
    %{search: search, folder: folder, params: params} = socket.assigns
    opts = [images_only: images_only?(params)]

    # A search reaches across folders on purpose; plain browsing stays in the folder.
    files =
      if search == "",
        do: Media.list_uploads(opts ++ [folder: folder_scope(folder)]),
        else: Media.list_uploads(opts ++ [search: search])

    assign(socket, files: files, subfolders: Media.child_folders(folder))
  end

  defp folder_scope(nil), do: :root
  defp folder_scope(folder), do: folder.id

  defp blank_to_nil(""), do: nil
  defp blank_to_nil(value), do: value

  @doc """
  The snippet Trix inserts: an `<img>` for images, else a labelled download `<a>` link.

  The alt text comes from the media item (`BbhWeb.Format.image_alt/1`), so a picture
  described once in the library is described the same in rich text.
  """
  def insert_html(upload) do
    url = media_url(upload)

    if Media.image?(upload) do
      ~s(<img src="#{url}" alt="#{esc(image_alt(upload))}">)
    else
      ~s(<a href="#{url}">#{esc(upload.title || upload.filename)}</a>)
    end
  end

  defp esc(value), do: value |> to_string() |> Plug.HTML.html_escape()

  @impl true
  def render(assigns) do
    assigns = assign(assigns, :crumbs, folder_crumbs(assigns.folder))

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
          class="flex max-h-[85vh] w-full max-w-3xl flex-col overflow-hidden rounded-lg bg-base-100 shadow-xl"
          phx-click-away="close"
          phx-target={@myself}
        >
          <div class="flex items-center justify-between border-b border-base-300 p-4">
            <h2 class="text-lg font-semibold">Aus Mediathek wählen</h2>
            <button
              type="button"
              phx-click="close"
              phx-target={@myself}
              aria-label="Schließen"
            >
              <.icon name="hero-x-mark" class="size-5" />
            </button>
          </div>

          <div class="min-h-0 flex-1 overflow-y-auto p-4">
            <nav class="mb-3 flex flex-wrap items-center gap-1 text-sm" aria-label="Ordnerpfad">
              <button
                type="button"
                phx-click="browse"
                phx-value-folder_id=""
                phx-target={@myself}
                class={["link", @crumbs == [] && "font-semibold"]}
              >
                Alle Medien
              </button>
              <span :for={{crumb, i} <- Enum.with_index(@crumbs)} class="flex items-center gap-1">
                <span aria-hidden="true" class="text-base-content/40">/</span>
                <button
                  :if={i < length(@crumbs) - 1}
                  type="button"
                  phx-click="browse"
                  phx-value-folder_id={crumb.id}
                  phx-target={@myself}
                  class="link"
                >
                  {crumb.name}
                </button>
                <span :if={i == length(@crumbs) - 1} class="font-semibold">{crumb.name}</span>
              </span>
            </nav>

            <div :if={@subfolders != []} class="mb-3 flex flex-wrap gap-2">
              <button
                :for={sf <- @subfolders}
                type="button"
                phx-click="browse"
                phx-value-folder_id={sf.id}
                phx-target={@myself}
                class="flex items-center gap-2 rounded-box border border-base-300 px-3 py-2 text-sm hover:bg-base-200"
              >
                <.icon name="hero-folder" class="size-5 text-primary" />
                {sf.name}
              </button>
            </div>

            <%!-- phx-submit as well as phx-change: without it, Enter in the search box
                  would be a real browser form submit and navigate away from the page. --%>
            <form
              id={"#{@id}-search"}
              phx-change="search"
              phx-submit="search"
              phx-target={@myself}
              class="mb-4"
            >
              <label class="input input-bordered flex items-center gap-2">
                <.icon name="hero-magnifying-glass" class="size-4 opacity-60" />
                <input
                  type="search"
                  name="search"
                  value={@search}
                  placeholder="In allen Ordnern suchen…"
                  phx-debounce="200"
                  autocomplete="off"
                  class="grow"
                />
              </label>
            </form>

            <div class="grid grid-cols-2 gap-3 sm:grid-cols-3 md:grid-cols-4">
              <button
                :for={u <- @files}
                type="button"
                phx-click="select"
                phx-value-id={u.id}
                phx-target={@myself}
                title={u.filename}
                class="group flex flex-col overflow-hidden rounded border border-base-300 text-left hover:border-primary"
              >
                <div class="flex aspect-square items-center justify-center bg-base-200">
                  <img
                    :if={Media.image?(u)}
                    src={media_url(u, width: 200, height: 200)}
                    alt=""
                    loading="lazy"
                    class="h-full w-full object-cover"
                  />
                  <.icon :if={!Media.image?(u)} name="hero-document" class="size-10 opacity-50" />
                </div>
                <span class="truncate p-1.5 text-xs">{u.title || u.filename}</span>
              </button>
            </div>

            <p :if={@files == []} class="py-8 text-center text-sm text-base-content/60">
              {empty_label(@search, @folder)}
            </p>
          </div>
        </div>
      </div>
    </div>
    """
  end

  # Folder path for the breadcrumb, root → current. Nesting is capped at two levels
  # (Bbh.Media.Folder), so a parent plus the folder itself is the whole trail.
  defp folder_crumbs(%Folder{parent: %Folder{} = parent} = folder), do: [parent, folder]
  defp folder_crumbs(%Folder{} = folder), do: [folder]
  defp folder_crumbs(_folder), do: []

  defp empty_label("", nil), do: "Noch keine Dateien außerhalb von Ordnern."
  defp empty_label("", _folder), do: "Dieser Ordner ist leer."
  defp empty_label(_search, _folder), do: "Keine Dateien gefunden."
end
