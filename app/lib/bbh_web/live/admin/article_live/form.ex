defmodule BbhWeb.Admin.ArticleLive.Form do
  use BbhWeb, :live_view

  import BbhWeb.Admin.MediaEditor, only: [media_editor: 1]

  alias Bbh.Content
  alias Bbh.Content.{Article, ArticleImage, Throne}
  alias BbhWeb.Admin.MediaEditor

  @statuses [{"Entwurf", "draft"}, {"Veröffentlicht", "published"}, {"Archiviert", "archived"}]

  @impl true
  def mount(params, _session, socket) do
    socket =
      allow_upload(socket, :image,
        accept: ~w(.jpg .jpeg .png .webp .gif),
        max_entries: 5,
        max_file_size: 20_000_000
      )
      |> assign(editing_media: nil)

    {:ok, apply_action(socket, socket.assigns.live_action, params)}
  end

  defp apply_action(socket, :new, _params) do
    article = %Article{status: "draft", date_published: Bbh.Time.now(), tags: []}

    socket
    |> assign(page_title: "Neuer Artikel", article: article)
    |> assign(images: [], show_throne: false)
    |> assign_form(Content.change_article(article))
  end

  defp apply_action(socket, :edit, %{"id" => id}) do
    article = Content.get_article!(id)

    socket
    |> assign(page_title: "Artikel bearbeiten", article: article, throne: article.throne)
    |> assign(show_throne: not is_nil(article.throne))
    |> assign(images: Content.list_article_images(id))
    |> assign(folder_options: Bbh.Media.folder_options())
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

  def handle_event("delete", %{"confirm" => confirm}, socket) do
    article = socket.assigns.article

    cond do
      not BbhWeb.Authz.can_delete?(socket.assigns.current_scope.user, article) ->
        {:noreply, put_flash(socket, :error, "Keine Berechtigung zum Löschen.")}

      confirm == article.slug ->
        {:ok, _} = Content.delete_article(article)

        {:noreply,
         socket |> put_flash(:info, "Artikel gelöscht.") |> push_navigate(to: ~p"/admin/artikel")}

      true ->
        {:noreply, put_flash(socket, :error, "Der eingegebene Wert stimmt nicht überein.")}
    end
  end

  def handle_event("validate_upload", _params, socket), do: {:noreply, socket}

  def handle_event("cancel_upload", %{"ref" => ref}, socket),
    do: {:noreply, cancel_upload(socket, :image, ref)}

  def handle_event("upload_images", _params, socket) do
    article = socket.assigns.article

    results =
      consume_uploaded_entries(socket, :image, fn %{path: path}, entry ->
        with {:ok, upload} <-
               Bbh.Media.store_file(path, %{
                 filename: entry.client_name,
                 content_type: entry.client_type
               }),
             {:ok, _} <- Content.add_article_image(article, upload.id) do
          {:ok, :stored}
        else
          {:error, reason} -> {:ok, {:rejected, reason}}
        end
      end)

    stored = Enum.count(results, &(&1 == :stored))
    rejected = Enum.count(results, &match?({:rejected, _}, &1))

    {:noreply, socket |> put_upload_result_flash(stored, rejected) |> reload_images()}
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

  def handle_event("edit_media", %{"upload_id" => id}, socket),
    do: {:noreply, assign(socket, :editing_media, Bbh.Media.get_upload!(id))}

  def handle_event("cancel_edit", _params, socket),
    do: {:noreply, assign(socket, :editing_media, nil)}

  # `:keep` means the editor stays open on the returned upload — that is how a rotation
  # shows its result and can be repeated (see BbhWeb.Admin.MediaEditor.submit/2).
  def handle_event("save_meta", %{"upload" => _} = params, socket) do
    {action, updated, {kind, message}} = MediaEditor.submit(socket.assigns.editing_media, params)

    {:noreply,
     socket
     |> assign(:editing_media, if(action == :keep, do: updated, else: nil))
     |> put_flash(kind, message)
     |> reload_images()}
  end

  def handle_event("set_preview_image", %{"img_id" => id}, socket) do
    case Content.set_article_preview_image(socket.assigns.article, id) do
      {:ok, _} ->
        {:noreply, socket |> put_flash(:info, "Vorschaubild festgelegt.") |> reload_images()}

      {:error, _} ->
        {:noreply, put_flash(socket, :error, "Bild konnte nicht gesetzt werden.")}
    end
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

  # A pick from the shared media picker (BbhWeb.Admin.MediaPicker); the modal stays open
  # so several images can be added in a row.
  @impl true
  def handle_info({:media_selected, %{"context" => "article_image"}, media_id}, socket) do
    {:ok, _} = Content.add_article_image(socket.assigns.article, media_id)
    {:noreply, reload_images(socket)}
  end

  defp reload_images(socket),
    do: assign(socket, :images, Content.list_article_images(socket.assigns.article.id))

  defp put_upload_result_flash(socket, stored, 0) when stored > 0,
    do: put_flash(socket, :info, "#{stored} Bild(er) hochgeladen und hinzugefügt.")

  defp put_upload_result_flash(socket, 0, rejected) when rejected > 0,
    do: put_flash(socket, :error, "#{rejected} Bild(er) konnten nicht hochgeladen werden.")

  defp put_upload_result_flash(socket, stored, rejected) when stored > 0 and rejected > 0,
    do: put_flash(socket, :warning, "#{stored} hochgeladen, #{rejected} abgelehnt.")

  defp put_upload_result_flash(socket, _stored, _rejected), do: socket

  defp upload_error_label(:too_large), do: "Datei ist zu groß (max. 20 MB)."
  defp upload_error_label(:too_many_files), do: "Zu viele Dateien (max. 5)."
  defp upload_error_label(:not_accepted), do: "Dateityp nicht erlaubt (nur Bilder)."
  defp upload_error_label(_), do: "Fehler beim Hochladen."

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
      {:ok, article} ->
        maybe_notify(nil, article)

        # Land on the new article's edit page so images/throne can be added right away.
        {:noreply,
         socket
         |> put_flash(:info, "Artikel erstellt.")
         |> push_navigate(to: ~p"/admin/artikel/#{article.id}/bearbeiten")}

      {:error, changeset} ->
        {:noreply, assign_form(socket, changeset)}
    end
  end

  defp save(socket, :edit, params) do
    old_status = socket.assigns.article.status

    case Content.update_article(socket.assigns.article, params) do
      {:ok, article} ->
        maybe_notify(old_status, article)

        # Stay on the edit page (reload the fresh record and rebuild the form).
        socket = reload_article(socket)

        {:noreply,
         socket
         |> assign_form(Content.change_article(socket.assigns.article))
         |> put_flash(:info, "Artikel gespeichert.")}

      {:error, changeset} ->
        {:noreply, assign_form(socket, changeset)}
    end
  end

  # Push the first time an article becomes published (skip throne-only entries).
  # Future-dated ("vorveröffentlichte") articles are pushed by the cron notifier
  # (Bbh.Workers.ArticlePublishNotifier) once their publish date passes.
  defp maybe_notify(old_status, %Article{status: "published", no_article: false} = article)
       when old_status != "published" do
    if publish_due?(article) do
      Bbh.Notifications.dispatch(fn -> Bbh.Workers.ArticlePublishNotifier.notify(article) end)
    end

    :ok
  end

  defp maybe_notify(_old_status, _article), do: :ok

  defp publish_due?(%Article{date_published: %DateTime{} = dt}),
    do: DateTime.compare(dt, Bbh.Time.now()) != :gt

  defp publish_due?(_), do: false

  defp assign_form(socket, changeset),
    do: assign(socket, :form, to_form(changeset, as: "article"))

  # Convert the flatpickr datetime string and comma-separated tags into what the changeset
  # expects. Only touch keys that are actually present — a missing "date_published" (e.g. a
  # form event that doesn't carry every field) must not clobber the stored value with nil.
  defp normalize(params) do
    params
    |> maybe_update("date_published", &parse_dt/1)
    |> maybe_update("tags", &parse_tags/1)
  end

  defp maybe_update(params, key, fun) do
    case params do
      %{^key => value} -> Map.put(params, key, fun.(value))
      _ -> params
    end
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
      <.header>
        {@page_title}
        <:actions>
          <.link
            :if={@live_action == :edit}
            href={~p"/aktuell/#{@article.year}/#{@article.slug}"}
            target="_blank"
            rel="noopener"
            class="btn btn-sm btn-soft gap-1"
          >
            <.icon name="hero-eye" class="size-4" /> {view_label(@article)}
          </.link>
        </:actions>
      </.header>

      <.form
        for={@form}
        id="article-form"
        phx-change="validate"
        phx-submit="save"
        class="mt-6 space-y-4"
      >
        <.input field={@form[:title]} label="Titel" required />
        <.input field={@form[:subtitle]} label="Untertitel" />
        <.input field={@form[:slug]} label="Slug" required />
        <.input field={@form[:status]} type="select" label="Status" options={statuses()} />
        <.datetime_field field={@form[:date_published]} label="Veröffentlicht am" />
        <p :if={@article.date_modified} class="-mt-1 text-xs text-base-content/50">
          Zuletzt geändert: {de_datetime(@article.date_modified)}
        </p>
        <.input field={@form[:author]} label="Autor" />
        <.input
          name="article[tags]"
          id="article_tags"
          value={tags_value(@form[:tags].value)}
          label="Tags (kommagetrennt)"
        />
        <.input field={@form[:no_article]} type="checkbox" label="Nur Thron-Anzeige (kein Artikel)" />
        <.rich_text field={@form[:body]} label="Text" />

        <div class="flex gap-2">
          <.button variant="primary" phx-disable-with="Speichern…">Speichern</.button>
          <.button navigate={~p"/admin/artikel"}>Abbrechen</.button>
        </div>
      </.form>

      <section :if={@live_action == :edit} class="mt-10">
        <h2 class="text-xl font-semibold">Bilder</h2>

        <p class="mt-1 text-sm text-base-content/60">
          Bildunterschrift, Alt-Text und Copyright gehören zum Bild selbst und werden in der
          <.link navigate={~p"/admin/medien"} class="link">Mediathek</.link>
          gepflegt — hier steht nur, wie das Bild in diesem Artikel verwendet wird.
        </p>

        <div class="mt-4 grid gap-4 sm:grid-cols-2">
          <div :for={img <- @images} class="rounded-box border border-base-300 p-3">
            <img
              src={media_url(img.media, width: 320, height: 200)}
              alt={image_alt(img)}
              class="mb-2 aspect-video w-full rounded object-cover"
            />
            <dl class="mb-2 space-y-0.5 text-xs text-base-content/70">
              <div class="flex gap-1">
                <dt class="shrink-0 font-medium">Unterschrift:</dt>
                <dd class="truncate">{image_caption(img.media) || "—"}</dd>
              </div>
              <div class="flex gap-1">
                <dt class="shrink-0 font-medium">Copyright:</dt>
                <dd class="truncate">{image_copyright(img.media) || "—"}</dd>
              </div>
            </dl>
            <button
              type="button"
              phx-click="edit_media"
              phx-value-upload_id={img.media.id}
              class="btn btn-outline btn-sm mb-2 w-full gap-1"
            >
              <.icon name="hero-pencil-square" class="size-4" /> Bild bearbeiten (Mediathek)
            </button>
            <button
              type="button"
              phx-click="set_preview_image"
              phx-value-img_id={img.id}
              disabled={img.use_as_article_image}
              class={[
                "btn btn-sm mb-2 w-full",
                (img.use_as_article_image && "btn-primary") || "btn-outline"
              ]}
            >
              {(img.use_as_article_image && "★ Vorschaubild") || "Als Vorschaubild festlegen"}
            </button>
            <.form :let={f} for={image_form(img)} id={"image-#{img.id}"} phx-submit="save_image">
              <input type="hidden" name="img_id" value={img.id} />
              <.input field={f[:show_caption]} type="checkbox" label="Bildunterschrift anzeigen" />
              <.input field={f[:use_as_throne_picture]} type="checkbox" label="Thronbild" />
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

        <form
          id="article-image-upload"
          phx-submit="upload_images"
          phx-change="validate_upload"
          class="mt-6"
        >
          <p class="mb-2 text-sm font-medium">Neues Bild hochladen</p>
          <div
            class="rounded-box border-2 border-dashed border-base-300 p-6 text-center"
            phx-drop-target={@uploads.image.ref}
          >
            <.live_file_input upload={@uploads.image} class="file-input file-input-bordered" />
            <p class="mt-2 text-sm text-base-content/60">
              JPG, PNG, WebP oder GIF · bis 20&nbsp;MB · max. 5 Dateien
            </p>
          </div>

          <div :if={@uploads.image.entries != []} class="mt-4 space-y-2">
            <div
              :for={entry <- @uploads.image.entries}
              class="flex items-center gap-3 rounded-box border border-base-300 p-2"
            >
              <.live_img_preview entry={entry} class="size-14 rounded object-cover" />
              <div class="flex-1">
                <p class="truncate text-sm">{entry.client_name}</p>
                <progress class="progress progress-primary w-full" value={entry.progress} max="100" />
              </div>
              <button
                type="button"
                phx-click="cancel_upload"
                phx-value-ref={entry.ref}
                class="btn btn-ghost btn-sm"
                aria-label="Abbrechen"
              >
                ✕
              </button>
            </div>
            <p :for={err <- upload_errors(@uploads.image)} class="text-sm text-error">
              {upload_error_label(err)}
            </p>
            <.button variant="primary" phx-disable-with="Lädt hoch…">Hochladen &amp; hinzufügen</.button>
          </div>
        </form>

        <div class="mt-6">
          <button
            type="button"
            phx-click="open"
            phx-target="#media-picker"
            phx-value-context="article_image"
            class="btn btn-outline gap-1"
          >
            <.icon name="hero-photo" class="size-4" /> Bild aus Mediathek hinzufügen
          </button>
          <p class="mt-1 text-xs text-base-content/50">
            Im Auswahlfenster durch die Ordner der
            <.link
              navigate={~p"/admin/medien"}
              class="link"
            >Mediathek</.link>
            navigieren. Hochgeladene Bilder landen dort automatisch.
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

        <.form
          :let={t}
          :if={@show_throne}
          for={@throne_form}
          id="throne-form"
          phx-submit="save_throne"
          class="mt-4 space-y-3"
        >
          <.input
            field={t[:type]}
            type="select"
            label="Typ"
            options={[
              {"König", "koenig"},
              {"Kaiser", "kaiser"},
              {"Stadtkaiser", "stadtkaiser"},
              {"Jungschützenkönig", "jungschuetzenkoenig"}
            ]}
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

      <.danger_zone
        :if={@live_action == :edit and BbhWeb.Authz.can_delete?(@current_scope.user, @article)}
        confirm_value={@article.slug}
      >
        Der Artikel „{@article.title}" wird mit allen Bildern dauerhaft gelöscht.
      </.danger_zone>
      <.live_component module={BbhWeb.Admin.MediaPicker} id="media-picker" />
      <.media_editor
        :if={@editing_media}
        upload={@editing_media}
        folder_options={@folder_options}
      />
    </Layouts.admin>
    """
  end

  # "Ansehen" when the article is actually public, "Vorschau" otherwise (draft,
  # scheduled/future-dated, or archived — the public page then shows a preview banner).
  defp view_label(article), do: if(article_live?(article), do: "Ansehen", else: "Vorschau")

  defp article_live?(%Article{status: "published", date_published: %DateTime{} = dt}),
    do: DateTime.compare(dt, Bbh.Time.now()) != :gt

  defp article_live?(_), do: false

  defp image_form(%ArticleImage{} = img),
    do: to_form(ArticleImage.changeset(img, %{}), as: "image")

  defp tags_value(tags) when is_list(tags), do: Enum.join(tags, ", ")
  defp tags_value(str) when is_binary(str), do: str
  defp tags_value(_), do: ""

  defp statuses, do: @statuses
end
