defmodule BbhWeb.Admin.ArticleLive.Form do
  use BbhWeb, :live_view

  import BbhWeb.Admin.BlockEditor, only: [block_editor: 1, normalize_block: 2]

  alias Bbh.Content
  alias Bbh.Content.{Article, Throne}

  @statuses [{"Entwurf", "draft"}, {"Veröffentlicht", "published"}, {"Archiviert", "archived"}]

  @impl true
  def mount(params, _session, socket) do
    {:ok, apply_action(socket, socket.assigns.live_action, params)}
  end

  defp apply_action(socket, :new, _params) do
    article = %Article{status: "draft", date_published: Bbh.Time.now(), tags: []}

    socket
    |> assign(page_title: "Neuer Artikel", article: article, throne: nil)
    |> assign(blocks: [], show_throne: false)
    |> assign_form(Content.change_article(article))
  end

  defp apply_action(socket, :edit, %{"id" => id}) do
    article = Content.get_article!(id)

    socket
    |> assign(page_title: "Artikel bearbeiten", article: article, throne: article.throne)
    |> assign(show_throne: not is_nil(article.throne))
    |> assign(blocks: Content.load_blocks(article))
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

  def handle_event("clear_article_image", _params, socket) do
    {:ok, _} = Content.set_article_image(socket.assigns.article, nil)
    {:noreply, socket |> put_flash(:info, "Artikelbild entfernt.") |> reload_blocks()}
  end

  ## Content blocks — handled by the shared BbhWeb.Admin.BlockEditor markup

  def handle_event("add_block", %{"type" => type}, socket) do
    {:ok, _} = Content.add_block(socket.assigns.article, type)
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
    direction = if dir == "up", do: :up, else: :down

    case Content.move_gallery_file(file.gallery_id, file, direction) do
      {:ok, _} ->
        {:noreply, reload_blocks(socket)}

      {:error, _reason} ->
        {:noreply, put_flash(socket, :error, "Bild konnte nicht verschoben werden.")}
    end
  end

  def handle_event("move", %{"pb_id" => pb_id, "dir" => dir}, socket) do
    direction = if dir == "up", do: :up, else: :down

    case Content.move_block(find_pb(socket, pb_id), direction) do
      {:ok, _} ->
        {:noreply, reload_blocks(socket)}

      {:error, _reason} ->
        {:noreply, put_flash(socket, :error, "Block konnte nicht verschoben werden.")}
    end
  end

  ## Throne

  def handle_event("add_throne_section", _params, socket) do
    {:noreply, assign(socket, :show_throne, true)}
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

  def handle_event("clear_throne_image", _params, socket) do
    with %Throne{} = throne <- socket.assigns.article.throne do
      {:ok, _} = Content.set_throne_image(throne, nil)
    end

    {:noreply,
     socket |> put_flash(:info, "Thronbild auf Artikelbild zurückgesetzt.") |> reload_blocks()}
  end

  ## Media picks from the shared media picker (BbhWeb.Admin.MediaPicker)

  # The `pb_id` the modal was opened with tells us which block the choice belongs to.
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
    # The block can be gone by the time the pick lands (deleted here or in another tab).
    case find_block(socket, pb_id) do
      {_pb, gallery} ->
        {:ok, _} = Content.add_gallery_file(gallery, id)
        {:noreply, reload_blocks(socket)}

      nil ->
        {:noreply, put_flash(socket, :error, "Dieser Block existiert nicht mehr.")}
    end
  end

  def handle_info({:media_selected, %{"context" => "article_image"}, media_id}, socket) do
    {:ok, _} = Content.set_article_image(socket.assigns.article, media_id)
    {:noreply, socket |> put_flash(:info, "Artikelbild gesetzt.") |> reload_blocks()}
  end

  def handle_info({:media_selected, %{"context" => "throne_image"}, media_id}, socket) do
    case socket.assigns.article.throne do
      %Throne{} = throne ->
        {:ok, _} = Content.set_throne_image(throne, media_id)
        {:noreply, socket |> put_flash(:info, "Thronbild gesetzt.") |> reload_blocks()}

      _ ->
        {:noreply, put_flash(socket, :error, "Bitte zuerst den Thron speichern.")}
    end
  end

  defp find_pb(socket, pb_id) do
    Enum.find_value(socket.assigns.blocks, fn {pb, _} -> pb.id == pb_id && pb end)
  end

  defp find_block(socket, pb_id) do
    Enum.find(socket.assigns.blocks, fn {pb, _} -> pb.id == pb_id end)
  end

  # Refresh the article (with its image + throne) and its blocks, leaving the throne form
  # and its open/closed state untouched — used after block and image edits.
  defp reload_blocks(socket) do
    article = Content.get_article!(socket.assigns.article.id)
    assign(socket, article: article, throne: article.throne, blocks: Content.load_blocks(article))
  end

  # Full reload including the throne form and its visibility — used after a throne save or
  # delete, which changes what the form is bound to.
  defp reload_article(socket) do
    socket
    |> reload_blocks()
    |> then(fn s ->
      s
      |> assign(show_throne: not is_nil(s.assigns.article.throne))
      |> assign_throne_form(Content.change_throne(throne_or_new(s.assigns.article)))
    end)
  end

  defp assign_throne_form(socket, changeset),
    do: assign(socket, :throne_form, to_form(changeset, as: "throne"))

  defp throne_or_new(%Article{throne: %Throne{} = t}), do: t
  defp throne_or_new(%Article{id: id}), do: %Throne{article_id: id}

  defp save(socket, :new, params) do
    case Content.create_article(params) do
      {:ok, article} ->
        maybe_notify(nil, article)

        # Land on the new article's edit page so image/blocks/throne can be added right away.
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

        socket = reload_blocks(socket)

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
        <.input field={@form[:title]} label="Titel" required phx-hook="SlugFromTitle" />
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

        <div class="flex gap-2">
          <.button variant="primary" phx-disable-with="Speichern…">Speichern</.button>
          <.button navigate={~p"/admin/artikel"}>Abbrechen</.button>
        </div>
      </.form>

      <p :if={@live_action == :new} class="mt-6 text-sm text-base-content/60">
        Artikelbild, Inhaltsblöcke und Thron können nach dem ersten Speichern hinzugefügt werden.
      </p>

      <section :if={@live_action == :edit} class="mt-10">
        <h2 class="text-xl font-semibold">Artikelbild</h2>
        <p class="mt-1 text-sm text-base-content/60">
          Das Titelbild des Artikels — und, sofern der Thron kein eigenes Bild hat, dessen
          Bild. Bildunterschrift und Copyright kommen aus der <.link
            navigate={~p"/admin/medien"}
            class="link"
          >Mediathek</.link>.
        </p>

        <div class="mt-3 flex items-center gap-3">
          <img
            :if={@article.image}
            src={media_url(@article.image, width: 240, height: 150)}
            alt={image_alt(@article.image)}
            class="aspect-video w-40 rounded object-cover"
          />
          <span
            :if={is_nil(@article.image)}
            class="flex aspect-video w-40 items-center justify-center rounded bg-base-300 text-xs text-base-content/60"
          >
            Kein Bild
          </span>
          <div class="flex flex-wrap gap-2">
            <button
              type="button"
              phx-click="open"
              phx-target="#media-picker"
              phx-value-context="article_image"
              class="btn btn-outline btn-sm"
            >
              {if @article.image, do: "Bild ändern", else: "Bild wählen"}
            </button>
            <button
              :if={@article.image}
              type="button"
              phx-click="clear_article_image"
              class="btn btn-ghost btn-sm text-error"
            >
              Entfernen
            </button>
          </div>
        </div>
      </section>

      <.block_editor :if={@live_action == :edit} blocks={@blocks} />

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

        <%!-- The throne picture is a persisted-throne concern: it needs a saved throne to
              attach to. Until then it silently inherits the article image. --%>
        <div :if={@show_throne && @throne} class="mt-4 rounded-box border border-base-300 p-3">
          <% throne_pic = @throne.image || @article.image %>
          <p class="mb-2 text-sm font-medium">Thronbild</p>
          <div class="flex items-center gap-3">
            <img
              :if={throne_pic}
              src={media_url(throne_pic, width: 200, height: 200)}
              alt={image_alt(throne_pic)}
              class="aspect-square w-28 rounded object-cover"
            />
            <span
              :if={is_nil(throne_pic)}
              class="flex aspect-square w-28 items-center justify-center rounded bg-base-300 text-center text-xs text-base-content/60"
            >
              Kein Bild
            </span>
            <div class="flex flex-col gap-1">
              <p :if={is_nil(@throne.image)} class="text-xs text-base-content/60">
                Erbt das Artikelbild.
              </p>
              <div class="flex flex-wrap gap-2">
                <button
                  type="button"
                  phx-click="open"
                  phx-target="#media-picker"
                  phx-value-context="throne_image"
                  class="btn btn-outline btn-sm"
                >
                  {if @throne.image, do: "Bild ändern", else: "Eigenes Bild wählen"}
                </button>
                <button
                  :if={@throne.image}
                  type="button"
                  phx-click="clear_throne_image"
                  class="btn btn-ghost btn-sm text-error"
                >
                  Auf Artikelbild zurücksetzen
                </button>
              </div>
            </div>
          </div>
        </div>
      </section>

      <.danger_zone
        :if={@live_action == :edit and BbhWeb.Authz.can_delete?(@current_scope.user, @article)}
        confirm_value={@article.slug}
      >
        Der Artikel „{@article.title}" wird mit allen Inhaltsblöcken dauerhaft gelöscht.
      </.danger_zone>
      <.live_component module={BbhWeb.Admin.MediaPicker} id="media-picker" />
    </Layouts.admin>
    """
  end

  # "Ansehen" when the article is actually public, "Vorschau" otherwise (draft,
  # scheduled/future-dated, or archived — the public page then shows a preview banner).
  defp view_label(article), do: if(article_live?(article), do: "Ansehen", else: "Vorschau")

  defp article_live?(%Article{status: "published", date_published: %DateTime{} = dt}),
    do: DateTime.compare(dt, Bbh.Time.now()) != :gt

  defp article_live?(_), do: false

  defp tags_value(tags) when is_list(tags), do: Enum.join(tags, ", ")
  defp tags_value(str) when is_binary(str), do: str
  defp tags_value(_), do: ""

  defp statuses, do: @statuses
end
