defmodule BbhWeb.Admin.ArticleLive.Form do
  use BbhWeb, :live_view

  alias Bbh.Content
  alias Bbh.Content.{Article, ArticleImage, Throne}

  @statuses [{"Entwurf", "draft"}, {"Veröffentlicht", "published"}, {"Archiviert", "archived"}]

  @impl true
  def mount(params, _session, socket) do
    {:ok, apply_action(socket, socket.assigns.live_action, params)}
  end

  defp apply_action(socket, :new, _params) do
    article = %Article{status: "draft", date_published: DateTime.utc_now(:second), tags: []}

    socket
    |> assign(page_title: "Neuer Artikel", article: article)
    |> assign(images: [], media_library: [], picker_search: "", show_throne: false)
    |> assign_form(Content.change_article(article))
  end

  defp apply_action(socket, :edit, %{"id" => id}) do
    article = Content.get_article!(id)

    socket
    |> assign(page_title: "Artikel bearbeiten", article: article, throne: article.throne)
    |> assign(show_throne: not is_nil(article.throne))
    |> assign(images: Content.list_article_images(id), media_library: Bbh.Media.list_uploads(), picker_search: "")
    |> assign_throne_form(Content.change_throne(throne_or_new(article)))
    |> assign_form(Content.change_article(article))
  end

  @impl true
  def handle_event("validate", %{"article" => params}, socket) do
    changeset =
      socket.assigns.article
      |> Content.change_article(normalize(params))
      |> Map.put(:action, :validate)

    {:noreply, assign_form(socket, changeset)}
  end

  def handle_event("save", %{"article" => params}, socket) do
    save(socket, socket.assigns.live_action, normalize(params))
  end

  def handle_event("add_image", %{"media_id" => media_id}, socket) do
    {:ok, _} = Content.add_article_image(socket.assigns.article, media_id)
    {:noreply, reload_images(socket)}
  end

  def handle_event("search_media", %{"search" => search}, socket) do
    {:noreply, assign(socket, picker_search: search, media_library: Bbh.Media.list_uploads(search: search))}
  end

  def handle_event("add_throne_section", _params, socket) do
    {:noreply, assign(socket, :show_throne, true)}
  end

  def handle_event("save_image", %{"img_id" => id, "image" => params}, socket) do
    id |> Content.get_article_image!() |> Content.update_article_image(params)
    {:noreply, socket |> put_flash(:info, "Bild gespeichert.") |> reload_images()}
  end

  def handle_event("delete_image", %{"img_id" => id}, socket) do
    id |> Content.get_article_image!() |> Content.delete_article_image()
    {:noreply, reload_images(socket)}
  end

  def handle_event("save_throne", %{"throne" => params}, socket) do
    article = socket.assigns.article
    params = Map.put(params, "article_id", article.id)

    result =
      case article.throne do
        %Throne{} = throne -> Content.update_throne(throne, params)
        _ -> Content.create_throne(params)
      end

    case result do
      {:ok, _} -> {:noreply, socket |> put_flash(:info, "Thron gespeichert.") |> reload_article()}
      {:error, changeset} -> {:noreply, assign_throne_form(socket, changeset)}
    end
  end

  def handle_event("delete_throne", _params, socket) do
    with %Throne{} = throne <- socket.assigns.article.throne, do: Content.delete_throne(throne)
    {:noreply, socket |> put_flash(:info, "Thron entfernt.") |> reload_article()}
  end

  defp reload_images(socket),
    do: assign(socket, :images, Content.list_article_images(socket.assigns.article.id))

  defp reload_article(socket) do
    article = Content.get_article!(socket.assigns.article.id)

    socket
    |> assign(article: article, throne: article.throne, show_throne: not is_nil(article.throne))
    |> assign(images: Content.list_article_images(article.id))
    |> assign_throne_form(Content.change_throne(throne_or_new(article)))
  end

  defp assign_throne_form(socket, changeset),
    do: assign(socket, :throne_form, to_form(changeset, as: "throne"))

  defp throne_or_new(%Article{throne: %Throne{} = t}), do: t
  defp throne_or_new(%Article{id: id}), do: %Throne{article_id: id}

  defp save(socket, :new, params) do
    case Content.create_article(params) do
      {:ok, _article} ->
        {:noreply,
         socket |> put_flash(:info, "Artikel erstellt.") |> push_navigate(to: ~p"/admin/artikel")}

      {:error, changeset} ->
        {:noreply, assign_form(socket, changeset)}
    end
  end

  defp save(socket, :edit, params) do
    case Content.update_article(socket.assigns.article, params) do
      {:ok, _article} ->
        {:noreply,
         socket |> put_flash(:info, "Artikel gespeichert.") |> push_navigate(to: ~p"/admin/artikel")}

      {:error, changeset} ->
        {:noreply, assign_form(socket, changeset)}
    end
  end

  defp assign_form(socket, changeset), do: assign(socket, :form, to_form(changeset, as: "article"))

  # Convert the datetime-local string and comma-separated tags into what the changeset expects.
  defp normalize(params) do
    params
    |> Map.update("date_published", nil, &parse_dt/1)
    |> Map.update("tags", [], &parse_tags/1)
  end

  defp parse_dt(v) when v in [nil, ""], do: nil

  defp parse_dt(v) when is_binary(v) do
    cond do
      Regex.match?(~r/^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}$/, v) -> v <> ":00Z"
      Regex.match?(~r/^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}$/, v) -> v <> "Z"
      true -> v
    end
  end

  defp parse_tags(list) when is_list(list), do: list

  defp parse_tags(str) when is_binary(str),
    do: str |> String.split(",") |> Enum.map(&String.trim/1) |> Enum.reject(&(&1 == ""))

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.admin flash={@flash} current_scope={@current_scope} active={:articles}>
      <.header>{@page_title}</.header>

      <.form for={@form} id="article-form" phx-change="validate" phx-submit="save" class="mt-6 space-y-4">
        <.input field={@form[:title]} label="Titel" required />
        <.input field={@form[:subtitle]} label="Untertitel" />
        <.input field={@form[:slug]} label="Slug" required />
        <.input field={@form[:status]} type="select" label="Status" options={statuses()} />
        <.input field={@form[:date_published]} type="datetime-local" label="Veröffentlicht am" />
        <.input field={@form[:author]} label="Autor" />
        <.input
          name="article[tags]"
          id="article_tags"
          value={tags_value(@form[:tags].value)}
          label="Tags (kommagetrennt)"
        />
        <.input field={@form[:no_article]} type="checkbox" label="Nur Thron-Anzeige (kein Artikel)" />
        <.input field={@form[:body]} type="textarea" label="Text (HTML)" rows="12" />

        <div class="flex gap-2">
          <.button variant="primary" phx-disable-with="Speichern…">Speichern</.button>
          <.button navigate={~p"/admin/artikel"}>Abbrechen</.button>
        </div>
      </.form>

      <section :if={@live_action == :edit} class="mt-10">
        <h2 class="text-xl font-semibold">Bilder</h2>

        <div class="mt-4 grid gap-4 sm:grid-cols-2">
          <div :for={img <- @images} class="rounded-box border border-base-300 p-3">
            <img
              src={media_url(img.media, width: 320, height: 200)}
              alt={img.title || ""}
              class="mb-2 aspect-video w-full rounded object-cover"
            />
            <.form :let={f} for={image_form(img)} id={"image-#{img.id}"} phx-submit="save_image">
              <input type="hidden" name="img_id" value={img.id} />
              <.input field={f[:title]} label="Bildunterschrift" />
              <.input field={f[:copyright]} label="Copyright" />
              <div class="grid grid-cols-2 gap-2">
                <.input field={f[:use_as_article_image]} type="checkbox" label="Titelbild" />
                <.input field={f[:use_as_throne_picture]} type="checkbox" label="Thronbild" />
              </div>
              <.input field={f[:sort]} type="number" label="Sortierung" />
              <div class="mt-2 flex gap-2">
                <.button variant="primary" class="btn btn-primary btn-sm" phx-disable-with="…">Speichern</.button>
                <button
                  type="button"
                  class="btn btn-ghost btn-sm text-error"
                  phx-click="delete_image"
                  phx-value-img_id={img.id}
                  data-confirm="Bild entfernen?"
                >
                  Entfernen
                </button>
              </div>
            </.form>
          </div>

          <p :if={@images == []} class="text-base-content/60">Noch keine Bilder.</p>
        </div>

        <div class="mt-4">
          <p class="mb-2 text-sm font-medium">Bild aus Mediathek hinzufügen</p>
          <form phx-change="search_media" class="mb-2">
            <input
              type="text"
              name="search"
              value={@picker_search}
              placeholder="Mediathek durchsuchen…"
              phx-debounce="300"
              class="input input-bordered w-full max-w-xs"
            />
          </form>
          <div class="grid max-h-72 grid-cols-3 gap-2 overflow-y-auto rounded-box border border-base-300 p-2 sm:grid-cols-4 md:grid-cols-6">
            <button
              :for={m <- @media_library}
              type="button"
              phx-click="add_image"
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
                + hinzufügen
              </span>
            </button>
            <p :if={@media_library == []} class="col-span-full p-2 text-sm text-base-content/60">
              Keine Bilder gefunden.
            </p>
          </div>
          <p class="mt-1 text-xs text-base-content/50">
            Bilder zuerst in der <.link navigate={~p"/admin/medien"} class="link">Mediathek</.link> hochladen.
          </p>
        </div>
      </section>

      <section :if={@live_action == :edit} class="mt-10">
        <h2 class="text-xl font-semibold">Thron</h2>
        <p :if={!@show_throne} class="mt-1 text-sm text-base-content/60">
          Kein Thron-Artikel.
          <button type="button" class="link link-primary" phx-click="add_throne_section">
            Thron-Angaben hinzufügen
          </button>
        </p>

        <.form :if={@show_throne} :let={t} for={@throne_form} id="throne-form" phx-submit="save_throne" class="mt-4 space-y-3">
          <.input
            field={t[:type]}
            type="select"
            label="Typ"
            options={[{"König", "koenig"}, {"Kaiser", "kaiser"}, {"Stadtkaiser", "stadtkaiser"}]}
          />
          <div class="grid grid-cols-2 gap-2">
            <.input field={t[:begin_year]} type="number" label="Beginn (Jahr)" />
            <.input field={t[:end_year]} type="number" label="Ende (Jahr)" />
          </div>
          <.input field={t[:king_title]} label="Regentenname (z. B. Gerd X.)" />
          <div class="grid grid-cols-2 gap-2">
            <.input field={t[:king]} label="König" />
            <.input field={t[:queen]} label="Königin" />
          </div>
          <div class="grid grid-cols-2 gap-2">
            <.input field={t[:moh1]} label="Ehrendame 1" />
            <.input field={t[:moh2]} label="Ehrendame 2" />
          </div>
          <div class="grid grid-cols-2 gap-2">
            <.input field={t[:loh1]} label="Ehrenherr 1" />
            <.input field={t[:loh2]} label="Ehrenherr 2" />
          </div>
          <div class="grid grid-cols-2 gap-2">
            <.input field={t[:cupbearer]} label="Mundschenk" />
            <.input field={t[:courtmarshal]} label="Oberhofmarschall" />
          </div>
          <div class="flex gap-2">
            <.button variant="primary" class="btn btn-primary btn-sm" phx-disable-with="…">Thron speichern</.button>
            <button
              :if={@throne}
              type="button"
              class="btn btn-ghost btn-sm text-error"
              phx-click="delete_throne"
              data-confirm="Thron wirklich entfernen?"
            >
              Thron entfernen
            </button>
          </div>
        </.form>
      </section>
    </Layouts.admin>
    """
  end

  defp image_form(%ArticleImage{} = img), do: to_form(ArticleImage.changeset(img, %{}), as: "image")

  defp tags_value(tags) when is_list(tags), do: Enum.join(tags, ", ")
  defp tags_value(str) when is_binary(str), do: str
  defp tags_value(_), do: ""

  defp statuses, do: @statuses
end
