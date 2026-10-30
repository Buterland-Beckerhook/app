defmodule Bbh.Media.Folders do
  @moduledoc """
  The media library's folder tree: listing it (in editor order, assembled in memory),
  creating, renaming, moving (with a depth cap and sibling renumbering under an advisory
  lock) and deleting folders. Uploads live in `Bbh.Media`; a folder only groups them.
  """

  import Ecto.Query
  alias Bbh.Ordering
  alias Bbh.Repo
  alias Bbh.Media.{Folder, Upload}

  # Editor order first, name only to break ties between folders that have never been
  # dragged (they all sit at the position the migration gave them).
  @folder_order [asc: :position, asc: :name]

  @doc """
  Top-level folders (parent_id nil), in editor order, with `children` filled in all the
  way down, every level in editor order.

  One query for the whole table, assembled in memory: a nested preload would need one
  query per level and a fixed depth spelled out in it, and the table is a handful of
  rows. Assembling by `parent_id` also means a folder deeper than the cap (which the
  changesets prevent, but a hand-edited row could create) still shows up in the tree
  instead of stranding its media.
  """
  def list_root_folders do
    by_parent =
      from(f in Folder, order_by: ^@folder_order)
      |> Repo.all()
      |> Enum.group_by(& &1.parent_id)

    attach_children(Map.get(by_parent, nil, []), by_parent)
  end

  defp attach_children(folders, by_parent) do
    Enum.map(folders, fn folder ->
      %{folder | children: attach_children(Map.get(by_parent, folder.id, []), by_parent)}
    end)
  end

  @doc """
  The whole folder tree in one go, for the media library's permanent tree view:
  root folders with their children (both in editor order) plus the file counts
  shown on every node.

  A count is the number the node actually lists when clicked, and the library lists a
  folder either alone or with its whole branch ("Unterordner einbeziehen"). So there are
  two: `counts` holds every folder's branch total, `direct` the files filed in each folder
  itself (only folders that have any). `unfiled` is the files in none. One grouped query
  covers the lot; per-node counting would be N+1.
  """
  def list_folder_tree do
    direct =
      Repo.all(from u in Upload, group_by: u.folder_id, select: {u.folder_id, count(u.id)})
      |> Map.new()

    roots = list_root_folders()

    %{
      roots: roots,
      counts: branch_counts(roots, direct),
      direct: Map.delete(direct, nil),
      # From the direct counts, so folding the branches cannot count a parent twice.
      total: direct |> Map.values() |> Enum.sum(),
      unfiled: Map.get(direct, nil, 0)
    }
  end

  defp branch_counts(folders, direct) do
    Enum.reduce(folders, %{}, fn folder, acc ->
      below = branch_counts(folder.children, direct)
      children = folder.children |> Enum.map(&Map.fetch!(below, &1.id)) |> Enum.sum()

      acc
      |> Map.merge(below)
      |> Map.put(folder.id, Map.get(direct, folder.id, 0) + children)
    end)
  end

  @doc """
  The ids a folder's branch spans — the folder and every folder below it — read off a
  loaded `list_folder_tree/0`. A folder missing from the tree (deleted since it was
  loaded) stands for itself alone.
  """
  def branch_ids(%{roots: roots}, id) do
    case find_folder(roots, id) do
      %Folder{} = folder -> folder_and_descendant_ids(folder)
      nil -> [id]
    end
  end

  defp find_folder(folders, id) do
    Enum.find_value(folders, fn folder ->
      if folder.id == id, do: folder, else: find_folder(folder.children, id)
    end)
  end

  defp folder_and_descendant_ids(%Folder{id: id, children: children}),
    do: [id | Enum.flat_map(children, &folder_and_descendant_ids/1)]

  @doc """
  A flat, indented `{label, value}` option list of all folders (plus a "no folder"
  entry) for a folder-select. Value `""` means the root.

  Takes already-loaded roots when the caller has them — the media library renders the
  tree and this select from the same data, and re-querying would double the preload on
  every folder change, upload, edit and drop.
  """
  def folder_options(roots \\ list_root_folders()) do
    [{"— Kein Ordner —", ""} | folder_option_list(roots, "")]
  end

  # Labelled with the full path: a bare "2026" is ambiguous once two parents hold one.
  defp folder_option_list(folders, prefix) do
    Enum.flat_map(folders, fn folder ->
      label = prefix <> folder.name
      [{label, folder.id} | folder_option_list(folder.children, label <> " / ")]
    end)
  end

  @doc """
  The sub-folders to offer while browsing `folder`: the root lists all top-level
  folders, any other folder its direct children (none on the deepest level).
  """
  def child_folders(nil), do: list_subfolders(nil)
  def child_folders(%Folder{id: id}), do: list_subfolders(id)

  @doc """
  Direct sub-folders of `parent_id` (nil = top level), in editor order.

  Like `get_folder/1`, a non-UUID is an empty result rather than an `Ecto.Query.CastError`
  — folder ids in this module reach it from URLs and drag payloads.
  """
  def list_subfolders(nil),
    do: Repo.all(from f in Folder, where: is_nil(f.parent_id), order_by: ^@folder_order)

  def list_subfolders(parent_id) do
    case cast_uuid(parent_id) do
      {:ok, uuid} ->
        Repo.all(from f in Folder, where: f.parent_id == ^uuid, order_by: ^@folder_order)

      :error ->
        []
    end
  end

  @doc """
  Fetch a folder by id, with its whole parent chain preloaded (see `Folder.path/1`), or
  `nil`.

  The id reaches this straight from a URL query string and from drag & drop payloads,
  so anything that is not a UUID is a miss rather than an `Ecto.Query.CastError`.
  """
  def get_folder(id) do
    with {:ok, uuid} <- cast_uuid(id),
         %Folder{} = folder <- Repo.get(Folder, uuid) do
      Repo.preload(folder, parent_chain())
    else
      _ -> nil
    end
  end

  # `parent: [parent: …]`, one level short of the cap — the deepest folder has
  # max_depth - 1 ancestors.
  defp parent_chain,
    do: Enum.reduce(3..Folder.max_depth()//1, :parent, fn _, acc -> [parent: acc] end)

  defp cast_uuid(id) when is_binary(id), do: Ecto.UUID.cast(id)
  defp cast_uuid(_id), do: :error

  def get_folder!(id), do: Repo.get!(Folder, id)

  def change_folder(%Folder{} = folder \\ %Folder{}, attrs \\ %{}),
    do: Folder.changeset(folder, attrs)

  @doc "Create a folder. `parent_id` nil = top level; nesting below the depth cap is rejected."
  def create_folder(attrs) do
    case normalize_parent_id(attrs["parent_id"] || attrs[:parent_id]) do
      {:ok, parent_id} -> do_create_folder(attrs, parent_id)
      :error -> {:error, unknown_parent(%Folder{})}
    end
  end

  defp do_create_folder(attrs, parent_id) do
    unwrap(
      Repo.transaction(fn ->
        lock_folder_tree()

        # Read under the lock rather than trusting a value read before it: move_folder/3
        # may be moving this very parent deeper, and the depth check has to see the
        # outcome of that race, not the state before it.
        tree = folder_index()

        %Folder{}
        |> Folder.changeset(attrs, depth(tree, parent_id))
        # Neither is cast from `attrs`: the position is ours to assign (a new folder
        # belongs at the bottom of its level, not jumping to the top), and parent_id has
        # been through normalize_parent_id/1, which cast/3 would undo.
        |> Ecto.Changeset.put_change(:parent_id, parent_id)
        |> Ecto.Changeset.put_change(:position, next_folder_position(parent_id))
        |> Repo.insert()
        |> or_rollback()
      end)
    )
  end

  def rename_folder(%Folder{} = folder, name),
    do: folder |> Folder.changeset(%{name: name}) |> Repo.update()

  @doc """
  Re-hang `folder` under `parent_id` (`nil` = top level) at `index` among its new
  siblings — the write behind dragging a folder in the media tree.

  Both affected levels are renumbered: the target so the folder lands where it was
  dropped, the old one so it does not keep a gap. All of it in one transaction, so a
  move the depth cap forbids (`Folder.move_changeset/4`) leaves the tree untouched
  and returns `{:error, changeset}`.
  """
  def move_folder(%Folder{} = folder, parent_id, index) do
    case normalize_parent_id(parent_id) do
      {:ok, parent_id} -> do_move_folder(folder, parent_id, index)
      :error -> {:error, unknown_parent(folder)}
    end
  end

  # `nil`/`""` mean the top level; anything else has to be a real UUID *before* it
  # reaches Repo.update. `cast/3` waves a malformed :binary_id through and the failure
  # then surfaces as an `Ecto.ChangeError` at dump time — an exception, not a changeset
  # error, so a hand-crafted drop payload would be a 500 rather than a flash. Casting
  # here also canonicalises the case, which matters because the id doubles as the map
  # key for the locked rows.
  defp normalize_parent_id(id) do
    case blank_to_nil(id) do
      nil -> {:ok, nil}
      value -> cast_uuid(value)
    end
  end

  defp unknown_parent(folder) do
    folder
    |> Ecto.Changeset.change()
    |> Ecto.Changeset.add_error(:parent_id, "Zielordner nicht gefunden")
  end

  defp do_move_folder(%Folder{} = folder, parent_id, index) do
    unwrap(
      Repo.transaction(fn ->
        lock_folder_tree()

        # Deleted between the caller's read and now — nothing left to move.
        locked = Repo.get(Folder, folder.id) || Repo.rollback(:not_found)

        tree = folder_index()

        moved =
          locked
          |> Folder.move_changeset(
            %{parent_id: parent_id},
            depth(tree, parent_id),
            branch(tree, locked.id)
          )
          |> Repo.update()
          |> or_rollback()

        renumber_level(parent_id, moved, index)
        if locked.parent_id != parent_id, do: renumber_level(locked.parent_id, nil, nil)

        # renumber_level/3 writes positions through update_all, which does not touch the
        # struct above — returning `moved` would report the pre-move position.
        Repo.get!(Folder, moved.id)
      end)
    )
  end

  # One transaction-scoped advisory lock guarding every write to the folder tree.
  #
  # Row locks on the pair {moved folder, new parent} are *not* enough, and sorting that
  # pair by id does not save it: renumber_level/3 rewrites the position of every sibling
  # in a level, taking a row lock on each in list order — and two concurrent moves build
  # different lists, so they reach the same rows in opposite orders. Postgres breaks the
  # cycle by killing one transaction (40P01), which surfaces as a raise, not an
  # `{:error, _}`, and takes the LiveView down with it. Reproduced before this was added.
  #
  # Locking the whole tree instead is the boring fix: it is a handful of rows, edits are
  # rare and human-paced, so the contention this serialises away costs nothing
  # measurable. It also covers the top-level create, which has no parent row to lock and
  # was therefore unprotected against a concurrent create racing on `max(position)`.
  @folder_tree_lock 0xBBF01D

  defp lock_folder_tree, do: Repo.query!("SELECT pg_advisory_xact_lock($1)", [@folder_tree_lock])

  defp or_rollback({:ok, value}), do: value
  defp or_rollback({:error, changeset}), do: Repo.rollback(changeset)

  # Repo.transaction/1 wraps whatever the function returned; the callers of these
  # writers expect the plain {:ok, folder} | {:error, changeset | reason} of a Repo call.
  defp unwrap({:ok, folder}), do: {:ok, folder}
  defp unwrap({:error, reason}), do: {:error, reason}

  # Renumber one level from 0. `moved` + `index` place a folder inside it; both nil just
  # closes the gap a departing folder left behind. `moved` is already stored under its
  # new parent at this point, so it is pulled out of the list before being re-inserted.
  defp renumber_level(parent_id, moved, index) do
    siblings =
      parent_id
      |> list_subfolders()
      |> Enum.reject(&(moved && &1.id == moved.id))

    ordered =
      if moved,
        do: List.insert_at(siblings, clamp(index, length(siblings)), moved),
        else: siblings

    Ordering.renumber(ordered, &set_folder_position!/2)
  end

  # The index comes from the browser. List.insert_at/3 would read a negative as "from
  # the end" and silently place the folder somewhere nobody dropped it.
  defp clamp(index, max) when is_integer(index), do: index |> max(0) |> min(max)
  defp clamp(_index, max), do: max

  defp set_folder_position!(id, position),
    do: Repo.update_all(from(f in Folder, where: f.id == ^id), set: [position: position])

  # The shape of the tree as plain ids, for the depth checks of the writers above. Read
  # whole and under the lock: a handful of rows, and a chain walked query by query could
  # see a concurrent move halfway.
  defp folder_index do
    pairs = Repo.all(from f in Folder, select: {f.id, f.parent_id})

    %{
      parents: Map.new(pairs),
      children: Enum.group_by(pairs, &elem(&1, 1), &elem(&1, 0))
    }
  end

  # The level a folder sits on, the top level being 1 and "no folder" 0. An id that is
  # not in the table counts as 0 too — the foreign key reports it with a proper message.
  defp depth(_index, nil), do: 0

  defp depth(index, id) do
    case Map.fetch(index.parents, id) do
      {:ok, parent_id} -> 1 + depth(index, parent_id)
      :error -> 0
    end
  end

  # A folder and everything below it: the ids, and how many levels deep it goes (a leaf
  # is 1).
  defp branch(index, id) do
    below = index.children |> Map.get(id, []) |> Enum.map(&branch(index, &1))

    %{
      ids: [id | Enum.flat_map(below, & &1.ids)],
      height: 1 + (below |> Enum.map(& &1.height) |> Enum.max(fn -> 0 end))
    }
  end

  defp next_folder_position(parent_id) do
    query = from f in Folder, select: max(f.position)

    query =
      case cast_uuid(parent_id) do
        {:ok, uuid} -> where(query, [f], f.parent_id == ^uuid)
        # nil, or a malformed id the changeset is about to reject anyway.
        :error -> where(query, [f], is_nil(f.parent_id))
      end

    (Repo.one(query) || -1) + 1
  end

  defp blank_to_nil(value) when value in [nil, ""], do: nil
  defp blank_to_nil(value), do: value

  @doc "Delete a folder. Its media move back to unfiled; sub-folders are removed (cascade)."
  def delete_folder(%Folder{} = folder), do: Repo.delete(folder)
end
