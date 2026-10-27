defmodule BbhWeb.Admin.TagLive.Index do
  @moduledoc """
  Schlagworte: every tag in use with its article count. Renaming fixes a typo on every
  article at once — onto an existing tag it merges the two; removing takes a tag off
  every article (admins only, like every delete). The list is derived from the
  articles (`Bbh.Content.list_tags/0`), so there is nothing to create here: a new tag
  comes into being in the article form.
  """
  use BbhWeb, :live_view

  alias Bbh.Content
  alias BbhWeb.AdminList

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign(:page_title, "Schlagworte")
     |> assign(:list_state, AdminList.init(sort: "name", dir: :asc))
     |> assign(:editing, nil)
     |> load_list()}
  end

  @impl true
  def handle_event("list-" <> action, params, socket),
    do: {:noreply, AdminList.handle(action, params, socket, &load_list/1)}

  def handle_event("edit", %{"tag" => tag}, socket),
    do: {:noreply, assign(socket, :editing, tag)}

  def handle_event("cancel", _params, socket), do: {:noreply, assign(socket, :editing, nil)}

  def handle_event("rename", %{"old" => old, "new" => new}, socket) do
    case Content.rename_tag(old, new) do
      {:ok, count} ->
        {:noreply,
         socket
         |> put_flash(:info, "„#{old}“ umbenannt (#{articles(count)}).")
         |> assign(:editing, nil)
         |> load_list()}

      {:error, message} ->
        {:noreply, put_flash(socket, :error, message)}
    end
  end

  def handle_event("delete", %{"tag" => tag}, socket) do
    if BbhWeb.Authz.can_delete?(socket.assigns.current_scope.user, :tag) do
      {:ok, count} = Content.delete_tag(tag)

      {:noreply,
       socket |> put_flash(:info, "„#{tag}“ entfernt (#{articles(count)}).") |> load_list()}
    else
      {:noreply, put_flash(socket, :error, "Keine Berechtigung zum Löschen.")}
    end
  end

  defp articles(1), do: "1 Artikel"
  defp articles(n), do: "#{n} Artikel"

  defp load_list(socket) do
    tags = Content.list_tags()

    meta =
      AdminList.process(tags, socket.assigns.list_state,
        search: [& &1.name],
        sort: %{"name" => &String.downcase(&1.name), "count" => & &1.count},
        per_page: 10_000
      )

    # Case variants ("Thron" / "thron") are almost always one tag typed twice.
    variants =
      tags
      |> Enum.group_by(&String.downcase(&1.name))
      |> Enum.filter(fn {_key, group} -> length(group) > 1 end)
      |> Enum.flat_map(fn {_key, group} -> Enum.map(group, & &1.name) end)
      |> MapSet.new()

    assign(socket,
      tags: meta.entries,
      list_meta: meta,
      names: Enum.map(tags, & &1.name),
      variants: variants
    )
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.admin flash={@flash} current_scope={@current_scope} active={:tags}>
      <.header>
        Schlagworte
        <:subtitle>
          Alle Tags der Artikel. Umbenennen ändert das Tag in allen Artikeln; gibt es den
          neuen Namen schon, werden beide zusammengeführt. Neue Tags entstehen im
          Artikelformular.
        </:subtitle>
      </.header>

      <.list_search q={@list_meta.q} placeholder="Nach Tag suchen…" />

      <datalist id="tag-names">
        <option :for={name <- @names} value={name} />
      </datalist>

      <.table
        id="tags"
        rows={@tags}
        row_id={&"tag-#{:erlang.phash2(&1.name)}"}
        sort={@list_meta.sort}
        dir={@list_meta.dir}
      >
        <:col :let={t} label="Tag" sort_key="name">
          <form
            :if={@editing == t.name}
            id="rename-form"
            phx-submit="rename"
            class="flex flex-wrap items-center gap-2"
          >
            <input type="hidden" name="old" value={t.name} />
            <input
              type="text"
              name="new"
              value={t.name}
              list="tag-names"
              autocomplete="off"
              aria-label={"Neuer Name für „#{t.name}“"}
              class="input input-sm min-w-48"
              phx-mounted={JS.focus()}
            />
            <.button variant="primary" class="btn-sm">Umbenennen</.button>
            <button type="button" phx-click="cancel" class="btn btn-sm">Abbrechen</button>
          </form>
          <span :if={@editing != t.name} class="font-medium">{t.name}</span>
          <span
            :if={@editing != t.name and MapSet.member?(@variants, t.name)}
            class="badge badge-sm badge-warning ml-1"
            title="Gibt es auch in anderer Schreibweise"
          >
            Schreibweise doppelt
          </span>
        </:col>
        <:col :let={t} label="Artikel" sort_key="count">
          <a href={~p"/suche?#{[tag: t.name]}"} target="_blank" class="link link-hover">
            {t.count}
          </a>
        </:col>
        <:action :let={t}>
          <.link
            phx-click={JS.push("edit", value: %{tag: t.name})}
            class="link link-primary"
            title="Umbenennen"
            aria-label={"„#{t.name}“ umbenennen"}
          >
            <.icon name="hero-pencil-square" class="size-5" />
          </.link>
          <.link
            :if={BbhWeb.Authz.can_delete?(@current_scope.user, :tag)}
            phx-click={JS.push("delete", value: %{tag: t.name})}
            data-confirm={"„#{t.name}“ aus #{articles(t.count)} entfernen?"}
            class="link link-error"
            title="Aus allen Artikeln entfernen"
            aria-label={"„#{t.name}“ aus allen Artikeln entfernen"}
          >
            <.icon name="hero-trash" class="size-5" />
          </.link>
        </:action>
      </.table>

      <p :if={@tags == []} class="mt-4 text-sm text-base-content/60">Keine Tags gefunden.</p>
    </Layouts.admin>
    """
  end
end
