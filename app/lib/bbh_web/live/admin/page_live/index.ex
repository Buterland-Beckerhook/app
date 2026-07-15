defmodule BbhWeb.Admin.PageLive.Index do
  use BbhWeb, :live_view

  alias Bbh.Content

  @impl true
  def mount(_params, _session, socket) do
    {:ok, assign(socket, page_title: "Seiten", pages: Content.list_pages())}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.admin flash={@flash} current_scope={@current_scope} active={:pages}>
      <.header>
        Seiten
        <:actions>
          <.button variant="primary" navigate={~p"/admin/seiten/neu"}>Neue Seite</.button>
        </:actions>
      </.header>

      <.table id="pages" rows={@pages}>
        <:col :let={p} label="Titel"><span class="font-medium">{p.title}</span></:col>
        <:col :let={p} label="Slug">{p.slug}</:col>
        <:col :let={p} label="Status">
          {if p.status == "published", do: "Veröffentlicht", else: "Entwurf"}
        </:col>
        <:action :let={p}>
          <.link
            navigate={~p"/admin/seiten/#{p.id}/bearbeiten"}
            class="link link-primary"
            title="Bearbeiten"
            aria-label="Bearbeiten"
          >
            <.icon name="hero-pencil-square" class="size-5" />
          </.link>
        </:action>
      </.table>
    </Layouts.admin>
    """
  end
end
