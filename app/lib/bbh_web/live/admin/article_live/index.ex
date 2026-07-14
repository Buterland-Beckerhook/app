defmodule BbhWeb.Admin.ArticleLive.Index do
  use BbhWeb, :live_view

  alias Bbh.Content

  @impl true
  def mount(_params, _session, socket) do
    {:ok, assign(socket, page_title: "Artikel", articles: Content.list_articles())}
  end

  @impl true
  def handle_event("delete", %{"id" => id}, socket) do
    id |> Content.get_article!() |> Content.delete_article()

    {:noreply,
     socket
     |> put_flash(:info, "Artikel gelöscht.")
     |> assign(:articles, Content.list_articles())}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.admin flash={@flash} current_scope={@current_scope} active={:articles}>
      <.header>
        Artikel
        <:actions>
          <.button variant="primary" navigate={~p"/admin/artikel/neu"}>Neuer Artikel</.button>
        </:actions>
      </.header>

      <.table id="articles" rows={@articles}>
        <:col :let={a} label="Titel">
          <span class="font-medium">{a.title}</span>
        </:col>
        <:col :let={a} label="Datum">{de_date(a.date_published)}</:col>
        <:col :let={a} label="Status">
          <span class={["badge", status_class(a.status)]}>{status_label(a.status)}</span>
        </:col>
        <:action :let={a}>
          <.link
            navigate={~p"/admin/artikel/#{a.id}/bearbeiten"}
            class="link link-primary"
            title="Bearbeiten"
            aria-label="Bearbeiten"
          >
            <.icon name="hero-pencil-square" class="size-5" />
          </.link>
        </:action>
        <:action :let={a}>
          <.link
            phx-click={JS.push("delete", value: %{id: a.id})}
            data-confirm="Diesen Artikel wirklich löschen?"
            class="link link-error"
            title="Löschen"
            aria-label="Löschen"
          >
            <.icon name="hero-trash" class="size-5" />
          </.link>
        </:action>
      </.table>
    </Layouts.admin>
    """
  end

  defp status_label("published"), do: "Veröffentlicht"
  defp status_label("archived"), do: "Archiviert"
  defp status_label(_), do: "Entwurf"

  defp status_class("published"), do: "badge-success"
  defp status_class("archived"), do: "badge-neutral"
  defp status_class(_), do: "badge-ghost"
end
