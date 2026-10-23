defmodule Bbh.Redirects do
  @moduledoc """
  Redirects (Weiterleitungen) for paths that no longer exist, plus a log of the paths
  that still end in a 404.

  Consulted **only** on the 404 path (`BbhWeb.Redirector`), so nothing here can shadow
  a live page and a normal request never pays for a lookup. Resolution order:

    1. **Rules** — editor-managed rows in `redirects`, exact before prefix (`/…/*`),
       longest prefix first. Served from a `:persistent_term` cache that every write
       through this module refreshes.
    2. **Legacy** — URLs of the old Hugo site that map onto current content by rule
       (`Bbh.Redirects.Legacy`): renamed slugs, front-matter aliases, the old section
       and feed URLs. Rules win, so any legacy mapping can be overridden in the admin.

  Paths are compared in normalized form — see `normalize_path/1`.
  """
  import Ecto.Query

  alias Bbh.Repo
  alias Bbh.Redirects.{Legacy, NotFoundPath, Redirect}

  @cache_key {__MODULE__, :rules}

  # Hard ceiling for the 404 log. Past it, known paths keep counting but new ones are
  # not added, so a scanner spraying random URLs cannot grow the table without bound.
  @max_not_found 5_000

  ## Paths

  @doc """
  Normalizes a request path or rule source for comparison: drops query string and
  fragment, percent-decodes (invalid encodings are kept as-is), lowercases, collapses
  repeated slashes and removes a trailing slash.

      iex> Bbh.Redirects.normalize_path("/Aktuell/2019/Pokal-und-Preisschie%C3%9Fen/?x=1")
      "/aktuell/2019/pokal-und-preisschießen"
  """
  def normalize_path(path) when is_binary(path) do
    path
    |> String.trim()
    |> String.split(["?", "#"], parts: 2)
    |> hd()
    |> decode()
    |> String.downcase()
    |> String.replace(~r{/+}, "/")
    |> ensure_leading_slash()
    |> trim_trailing_slash()
  end

  defp decode(path) do
    decoded = URI.decode(path)
    if String.valid?(decoded), do: decoded, else: path
  rescue
    ArgumentError -> path
  end

  defp ensure_leading_slash("/" <> _ = path), do: path
  defp ensure_leading_slash(path), do: "/" <> path

  defp trim_trailing_slash("/"), do: "/"
  defp trim_trailing_slash(path), do: String.trim_trailing(path, "/")

  @doc "Whether `target` is an acceptable redirect target: a site path or an http(s) URL."
  def valid_target?("//" <> _), do: false
  def valid_target?("/" <> _), do: true

  def valid_target?(target) when is_binary(target) do
    case URI.parse(target) do
      %URI{scheme: scheme, host: host} when scheme in ["http", "https"] and is_binary(host) ->
        host != ""

      _ ->
        false
    end
  end

  def valid_target?(_), do: false

  @doc "Whether a (normalized) rule source matches a (normalized) path."
  def source_matches?(source, path) do
    if Redirect.prefix_source?(source) do
      base = String.trim_trailing(source, "/*")
      path == base or String.starts_with?(path, base <> "/")
    else
      path == source
    end
  end

  ## Resolution

  @doc """
  What a request for `path` (raw or normalized) should do once no route served it.

    * `{:rule, %{id:, target:, permanent:}}` — an editor-managed redirect
    * `{:legacy, target}` — an old Hugo URL that maps onto current content (always
      permanent)
    * `nil` — a genuine 404
  """
  def resolve(path) do
    path = normalize_path(path)

    case match_rule(path) do
      nil ->
        case Legacy.resolve(path) do
          nil -> nil
          target -> {:legacy, target}
        end

      rule ->
        {:rule, rule}
    end
  end

  defp match_rule(path) do
    %{exact: exact, prefixes: prefixes} = rules()

    Map.get(exact, path) ||
      Enum.find_value(prefixes, fn {source, rule} -> source_matches?(source, path) && rule end)
  end

  @doc "Counts a hit on a rule. Best effort: a failure never affects the redirect."
  def track_hit(id) do
    now = DateTime.utc_now() |> DateTime.truncate(:second)

    from(r in Redirect, where: r.id == ^id)
    |> Repo.update_all(inc: [hits: 1], set: [last_hit_at: now])

    :ok
  end

  defp rules do
    if cache?() do
      case :persistent_term.get(@cache_key, nil) do
        nil -> tap(load_rules(), &:persistent_term.put(@cache_key, &1))
        rules -> rules
      end
    else
      load_rules()
    end
  end

  defp load_rules do
    {prefixes, exact} =
      from(r in Redirect,
        select: {r.source_path, %{id: r.id, target: r.target, permanent: r.permanent}}
      )
      |> Repo.all()
      |> Enum.split_with(fn {source, _} -> Redirect.prefix_source?(source) end)

    %{
      exact: Map.new(exact),
      prefixes: Enum.sort_by(prefixes, fn {source, _} -> -String.length(source) end)
    }
  end

  # Erase only; the next lookup rebuilds it, so a burst of admin writes rebuilds once.
  # (A persistent_term erase triggers a global GC scan — fine at admin-edit frequency.)
  defp refresh_cache do
    if cache?(), do: :persistent_term.erase(@cache_key)
    :ok
  end

  # Off in test: the cache is node-global, async tests run in separate sandboxes.
  defp cache?, do: Application.get_env(:bbh, __MODULE__, [])[:cache] != false

  ## Rules CRUD

  @doc "All rules, most recently changed first."
  def list_redirects do
    Repo.all(from r in Redirect, order_by: [desc: r.updated_at])
  end

  def get_redirect!(id), do: Repo.get!(Redirect, id)

  def change_redirect(%Redirect{} = redirect, attrs \\ %{}),
    do: Redirect.changeset(redirect, attrs)

  @doc """
  Creates a rule. On success the 404-log entries it now covers are dropped — they
  have been dealt with.
  """
  def create_redirect(attrs) do
    %Redirect{}
    |> Redirect.changeset(attrs)
    |> Repo.insert()
    |> after_write()
  end

  def update_redirect(%Redirect{} = redirect, attrs) do
    redirect
    |> Redirect.changeset(attrs)
    |> Repo.update()
    |> after_write()
  end

  def delete_redirect(%Redirect{} = redirect) do
    redirect
    |> Repo.delete()
    |> tap(fn result -> if match?({:ok, _}, result), do: refresh_cache() end)
  end

  defp after_write({:ok, %Redirect{} = redirect} = result) do
    refresh_cache()
    dismiss_covered(redirect.source_path)
    result
  end

  defp after_write(error), do: error

  defp dismiss_covered(source) do
    query =
      if Redirect.prefix_source?(source) do
        base = String.trim_trailing(source, "/*")
        pattern = escape_like(base) <> "/%"
        from n in NotFoundPath, where: n.path == ^base or like(n.path, ^pattern)
      else
        from n in NotFoundPath, where: n.path == ^source
      end

    Repo.delete_all(query)
  end

  defp escape_like(value), do: String.replace(value, ["\\", "%", "_"], &("\\" <> &1))

  ## 404 log

  @doc """
  Records a 404 for `path` (normalized here). `referrer` is an external referrer URL
  or nil; only its host and path are kept.
  """
  def record_not_found(path, referrer \\ nil) do
    path = path |> normalize_path() |> String.slice(0, 1000)
    referrer = strip_referrer(referrer)
    now = DateTime.utc_now() |> DateTime.truncate(:second)

    set = if referrer, do: [last_seen_at: now, referrer: referrer], else: [last_seen_at: now]

    {updated, _} =
      from(n in NotFoundPath, where: n.path == ^path)
      |> Repo.update_all(inc: [hits: 1], set: set)

    if updated == 0 and Repo.aggregate(NotFoundPath, :count) < @max_not_found do
      Repo.insert(
        %NotFoundPath{
          path: path,
          referrer: referrer,
          first_seen_at: now,
          last_seen_at: now
        },
        on_conflict: [inc: [hits: 1], set: [last_seen_at: now]],
        conflict_target: :path
      )
    end

    :ok
  end

  defp strip_referrer(nil), do: nil

  defp strip_referrer(url) when is_binary(url) do
    case URI.parse(url) do
      %URI{host: host, path: path} when is_binary(host) and host != "" ->
        String.slice(host <> (path || ""), 0, 500)

      _ ->
        nil
    end
  end

  @doc "The 404 log, most frequent first."
  def list_not_found(limit \\ 200) do
    Repo.all(
      from n in NotFoundPath, order_by: [desc: n.hits, desc: n.last_seen_at], limit: ^limit
    )
  end

  @doc "Removes one 404-log entry (\"Ignorieren\")."
  def delete_not_found(id) do
    from(n in NotFoundPath, where: n.id == ^id) |> Repo.delete_all()
    :ok
  end

  @doc "Drops 404-log entries not seen for `days` days. Returns the number removed."
  def prune_not_found(days \\ 90) do
    cutoff = DateTime.utc_now() |> DateTime.add(-days, :day)
    {count, _} = from(n in NotFoundPath, where: n.last_seen_at < ^cutoff) |> Repo.delete_all()
    count
  end
end
