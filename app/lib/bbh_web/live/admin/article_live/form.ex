defmodule BbhWeb.Admin.ArticleLive.Form do
  use BbhWeb, :live_view

  alias Bbh.Content
  alias Bbh.Content.Article

  @statuses [{"Entwurf", "draft"}, {"Veröffentlicht", "published"}, {"Archiviert", "archived"}]

  @impl true
  def mount(params, _session, socket) do
    {:ok, apply_action(socket, socket.assigns.live_action, params)}
  end

  defp apply_action(socket, :new, _params) do
    article = %Article{status: "draft", date_published: DateTime.utc_now(:second), tags: []}

    socket
    |> assign(page_title: "Neuer Artikel", article: article)
    |> assign_form(Content.change_article(article))
  end

  defp apply_action(socket, :edit, %{"id" => id}) do
    article = Content.get_article!(id)

    socket
    |> assign(page_title: "Artikel bearbeiten", article: article)
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
    </Layouts.admin>
    """
  end

  defp tags_value(tags) when is_list(tags), do: Enum.join(tags, ", ")
  defp tags_value(str) when is_binary(str), do: str
  defp tags_value(_), do: ""

  defp statuses, do: @statuses
end
