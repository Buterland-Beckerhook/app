defmodule BbhWeb.AdminList do
  @moduledoc """
  Shared search / sort / pagination for the admin listing LiveViews.

  The admin datasets are small (a club website), so this filters, sorts and paginates
  the already-loaded list in memory instead of pushing it into each context's queries.
  A LiveView keeps a `:list_state` assign, forwards its `"list-*"` events here, and
  provides a `load_list/1` that calls `process/3` with its search + sort config.

  ## Wiring an index LiveView

      def mount(_params, _session, socket) do
        {:ok,
         socket
         |> assign(:list_state, AdminList.init(sort: "date_published", dir: :desc))
         |> load_list()}
      end

      def handle_event("list-" <> action, params, socket),
        do: {:noreply, AdminList.handle(action, params, socket, &load_list/1)}

      defp load_list(socket) do
        meta =
          AdminList.process(Content.list_articles(), socket.assigns.list_state,
            search: [& &1.title],
            sort: %{"title" => & &1.title, "date_published" => & &1.date_published}
          )

        assign(socket, articles: meta.entries, list_meta: meta)
      end
  """

  @per_page 20

  @type state :: %{q: String.t(), sort: String.t() | nil, dir: :asc | :desc, page: pos_integer()}

  @doc "Initial list state. Options: `:sort` (default column key) and `:dir` (`:asc`/`:desc`)."
  @spec init(keyword()) :: state()
  def init(opts \\ []) do
    %{q: "", sort: opts[:sort], dir: opts[:dir] || :asc, page: 1}
  end

  @doc """
  Handle a `"list-<action>"` event, update `:list_state`, and reload via `loader`.

  `loader` receives the socket with the updated state and returns the socket
  (typically after re-running `process/3` and re-assigning the rows).
  """
  def handle(action, params, socket, loader) when is_function(loader, 1) do
    state = update_state(socket.assigns.list_state, action, params)
    loader.(Phoenix.Component.assign(socket, :list_state, state))
  end

  defp update_state(state, "filter", params),
    do: %{state | q: params["q"] || "", page: 1}

  defp update_state(state, "sort", %{"key" => key}), do: toggle_sort(state, key)

  defp update_state(state, "page", %{"page" => page}),
    do: %{state | page: to_int(page, state.page)}

  defp update_state(state, _action, _params), do: state

  @doc "Toggle sort: same column flips direction, a new column starts ascending. Resets page."
  def toggle_sort(%{sort: key, dir: dir} = state, key),
    do: %{state | dir: flip(dir), page: 1}

  def toggle_sort(state, key), do: %{state | sort: key, dir: :asc, page: 1}

  defp flip(:asc), do: :desc
  defp flip(_), do: :asc

  @doc """
  Filter, sort and paginate `list` according to `state`.

  Options:

    * `:search` — list of accessor funs; a row matches if any accessor's string value
      contains the query (case-insensitive).
    * `:sort` — map of `sort key => accessor fun`. Only listed keys are sortable.
    * `:per_page` — page size (default #{@per_page}).

  Returns `%{entries:, page:, per_page:, total:, total_pages:, sort:, dir:, q:}`.
  """
  def process(list, state, opts) do
    per_page = opts[:per_page] || @per_page

    sorted =
      list
      |> filter(state.q, opts[:search] || [])
      |> sort(state.sort, state.dir, opts[:sort] || %{})

    total = length(sorted)
    total_pages = max(ceil(total / per_page), 1)
    page = state.page |> max(1) |> min(total_pages)
    entries = Enum.slice(sorted, (page - 1) * per_page, per_page)

    %{
      entries: entries,
      page: page,
      per_page: per_page,
      total: total,
      total_pages: total_pages,
      sort: state.sort,
      dir: state.dir,
      q: state.q
    }
  end

  defp filter(list, q, fields) when is_binary(q) do
    case String.trim(q) do
      "" ->
        list

      term ->
        needle = String.downcase(term)

        Enum.filter(list, fn item ->
          Enum.any?(fields, fn accessor ->
            item |> accessor.() |> to_string() |> String.downcase() |> String.contains?(needle)
          end)
        end)
    end
  end

  defp sort(list, nil, _dir, _sorts), do: list

  defp sort(list, key, dir, sorts) do
    case Map.fetch(sorts, key) do
      {:ok, accessor} -> Enum.sort_by(list, &sort_key(accessor.(&1)), sorter(dir))
      :error -> list
    end
  end

  # Normalize values so mixed types compare sensibly and dates sort chronologically
  # (a raw %DateTime{} compares by Erlang term order, which is not chronological).
  defp sort_key(%DateTime{} = dt), do: DateTime.to_unix(dt)
  defp sort_key(%Date{} = d), do: Date.to_gregorian_days(d)
  defp sort_key(s) when is_binary(s), do: String.downcase(s)
  defp sort_key(v), do: v

  # nil always sorts last, regardless of direction.
  defp sorter(dir) do
    fn a, b ->
      cond do
        a == b -> true
        is_nil(a) -> false
        is_nil(b) -> true
        dir == :desc -> a >= b
        true -> a <= b
      end
    end
  end

  defp to_int(value, fallback) do
    case Integer.parse(to_string(value)) do
      {n, _} -> n
      :error -> fallback
    end
  end
end
