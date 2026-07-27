defmodule Bbh.Media do
  @moduledoc """
  Media storage and on-demand responsive variants (libvips via `Image`).

  Originals live under `:uploads_dir` keyed by `storage_key`. Requesting a size
  produces a cached WebP variant under `:media_cache_dir` (regenerable, so it is
  excluded from backups). Replaces Directus asset transforms.
  """
  import Ecto.Query
  alias Bbh.Ordering
  alias Bbh.Repo
  alias Bbh.Media.{Folder, Upload}

  @content_types %{
    ".jpg" => "image/jpeg",
    ".jpeg" => "image/jpeg",
    ".png" => "image/png",
    ".webp" => "image/webp",
    ".gif" => "image/gif",
    ".avif" => "image/avif",
    ".svg" => "image/svg+xml",
    ".pdf" => "application/pdf"
  }

  # Canonical extension per detected (magic-byte) type. The storage key and stored
  # content_type are derived from the *actual* bytes, never the client-supplied type.
  @ext_for_type %{
    "image/jpeg" => ".jpg",
    "image/png" => ".png",
    "image/gif" => ".gif",
    "image/webp" => ".webp",
    "image/avif" => ".avif",
    "image/svg+xml" => ".svg",
    "application/pdf" => ".pdf"
  }

  # Raster/vector image types we can derive responsive variants and dimensions from.
  # PDFs are stored as-is (documents), so they are excluded here.
  @image_types ~w(image/jpeg image/png image/gif image/webp image/avif image/svg+xml)

  # Types we may rewrite in place when rotating. GIF is out (a rewrite would drop the
  # animation), SVG is out (vector markup, not pixels), PDFs are not images at all.
  @rotatable_types ~w(image/jpeg image/png image/webp image/avif)

  # Rotation is offered in quarter turns only — that is what editors ask for, and vips
  # does it as a discrete pixel shuffle rather than a resampling pass.
  @rotations [90, 180, 270]

  # Reject absurdly large images up front (a "decompression bomb": small on disk,
  # gigapixels decoded). Well above any real camera (~50 MP) but far below the
  # sizes that blow up native memory. The byte-size limit lives in the LiveView.
  # Overridable via config (`:bbh, :max_image_pixels`) for tuning without a rebuild.
  @default_max_pixels 100 * 1_000_000

  # Square admin thumbnails (media library grid, picker, editor). Generated at
  # upload time so those views — which request one variant per image at once —
  # open against a warm cache instead of a cold-cache decode burst.
  @prewarm_variants [{120, 120}, {200, 200}, {300, 300}]

  @doc "True for a stored content type we treat as a displayable image (not a PDF/document)."
  def image_type?(type), do: type in @image_types

  @doc "True if the upload is a displayable image (has an image thumbnail)."
  def image?(%Upload{content_type: type}), do: image_type?(type)

  @doc "True if the upload's original may be rewritten by a rotation."
  def rotatable?(%Upload{content_type: type}), do: type in @rotatable_types

  @doc "The rotation angles the editor offers (quarter turns, clockwise)."
  def rotations, do: @rotations

  def uploads_dir, do: Application.fetch_env!(:bbh, :uploads_dir)
  def cache_dir, do: Application.fetch_env!(:bbh, :media_cache_dir)

  def get_by_key(key), do: Repo.get_by(Upload, storage_key: key)

  @doc """
  List uploads, optionally filtered by `:search` (filename/title), `:folder`
  (`:root` = unfiled, a folder id, a list of folder ids, or absent = all),
  `:images_only`, and `:sort`.

  Note the asymmetry at the edges of `:folder`: absent means every file, while `[]` means
  none. A caller building the list from a selection has to decide which of the two an
  empty selection is; it will not raise either way.
  """
  def list_uploads(opts \\ []) do
    from(u in Upload)
    |> filter_search(opts[:search])
    |> filter_folder(Keyword.get(opts, :folder, :all))
    |> filter_images_only(opts[:images_only])
    |> sort_uploads(opts[:sort] || "newest")
    |> Repo.all()
  end

  defp filter_search(query, search) when is_binary(search) and search != "" do
    like = "%#{String.replace(search, "%", "\\%")}%"
    from u in query, where: ilike(u.filename, ^like) or ilike(u.title, ^like)
  end

  defp filter_search(query, _), do: query

  defp filter_folder(query, :all), do: query

  defp filter_folder(query, root) when root in [:root, nil, ""],
    do: where(query, [u], is_nil(u.folder_id))

  # A folder scope can span more than one folder: the media library lists a folder
  # together with its sub-folders, so selecting a parent shows the whole branch.
  defp filter_folder(query, ids) when is_list(ids),
    do: where(query, [u], u.folder_id in ^ids)

  defp filter_folder(query, folder_id), do: where(query, [u], u.folder_id == ^folder_id)

  defp filter_images_only(query, true), do: where(query, [u], u.content_type in ^@image_types)
  defp filter_images_only(query, _), do: query

  defp sort_uploads(query, "oldest"), do: from(u in query, order_by: [asc: u.inserted_at])
  defp sort_uploads(query, "name"), do: from(u in query, order_by: [asc: u.filename])
  defp sort_uploads(query, _newest), do: from(u in query, order_by: [desc: u.inserted_at])
  def get_upload!(id), do: Repo.get!(Upload, id)

  @doc """
  Fetch an upload by id, or `nil`.

  The tolerant twin of `get_upload!/1`, for ids that arrive from a drag & drop payload
  rather than from markup the server rendered: a non-UUID is a miss instead of an
  `Ecto.Query.CastError` that would take the LiveView down.
  """
  def get_upload(id) do
    case cast_uuid(id) do
      {:ok, uuid} -> Repo.get(Upload, uuid)
      :error -> nil
    end
  end

  def change_upload(%Upload{} = upload, attrs \\ %{}), do: Upload.update_changeset(upload, attrs)

  # Reindexed like the content writers in Bbh.Content: a gallery block's searchable text
  # is now the caption/title of its media items, so editing one here changes what the
  # site search should find.
  def update_upload(%Upload{} = upload, attrs) do
    # The folder select submits "" for "no folder" and the column is nullable, so the
    # blank→nil is folded in here rather than repeated at each caller.
    changeset = Upload.update_changeset(upload, normalize_folder_id(attrs))
    result = Repo.update(changeset)

    # A focal-point edit reframes every cover crop, so the cached variants are now stale —
    # drop them like a rotation does (rotate_upload/2). Only fires when the value truly
    # changed (Ecto omits unchanged fields from `changes`), so plain title/folder edits
    # keep the warm cache. The correct crop already regenerates on demand via the fx/fy
    # URL params; this just reclaims the orphaned files the edit would otherwise leave.
    with {:ok, saved} <- result, true <- focal_changed?(changeset) do
      purge_variants(saved)
    end

    Bbh.Search.reindex_after(result)
  end

  defp focal_changed?(%Ecto.Changeset{changes: changes}) do
    Map.has_key?(changes, :focal_point_x) or Map.has_key?(changes, :focal_point_y)
  end

  defp normalize_folder_id(%{"folder_id" => _} = attrs),
    do: Map.update!(attrs, "folder_id", &blank_to_nil/1)

  defp normalize_folder_id(%{folder_id: _} = attrs),
    do: Map.update!(attrs, :folder_id, &blank_to_nil/1)

  defp normalize_folder_id(attrs), do: attrs

  @doc """
  Move an upload into a folder. `nil` — or the `""` the "Ohne Ordner" drop target sends —
  moves it back to the unfiled level.
  """
  def move_upload(%Upload{} = upload, folder_id) do
    upload
    |> Upload.update_changeset(%{folder_id: blank_to_nil(folder_id)})
    |> Repo.update()
  end

  ## Rotation

  @doc """
  Rotate the stored original clockwise by 90, 180 or 270 degrees.

  The original file is rewritten (EXIF orientation is baked in first, so the result
  cannot be double-rotated by a viewer), which is what makes the new orientation show
  up everywhere — variants, downloads, and images embedded in rich text alike. The new
  bytes are written to a temporary file and only moved into place once vips succeeded,
  so a failure leaves the original untouched.

  Dimensions and byte size are re-read from the written file and the focal point is turned
  with the image. `revision` is bumped, which busts two caches at once: it rides on media
  URLs as `?v=` (the browser) and joins the variant cache key (the disk). The upload's
  cached variant directory is dropped too — that only frees the space, the key change is
  what makes a stale variant unreachable.

  Returns `{:error, :not_rotatable}` for GIF/SVG/PDF and `{:error, :invalid_angle}` for
  anything that is not a quarter turn.
  """
  def rotate_upload(%Upload{} = upload, degrees) when degrees in @rotations do
    if rotatable?(upload), do: do_rotate(upload, degrees), else: {:error, :not_rotatable}
  end

  def rotate_upload(%Upload{}, _degrees), do: {:error, :invalid_angle}

  # sobelow_skip ["Traversal.FileModule"]
  # source is uploads_dir/<db storage_key> (format-validated at creation, not
  # user-updatable — see Upload.changeset/2); temp is that path plus a generated suffix.
  defp do_rotate(%Upload{} = upload, degrees) do
    source = Path.join(uploads_dir(), upload.storage_key)

    # Same directory as the original, so the move is a rename within one filesystem and
    # therefore atomic — a half-written original is never visible. It also means the temp
    # file is briefly reachable under /media/<key>.rot-<n>.<ext>; harmless, since the
    # original it is derived from is public at the neighbouring path anyway.
    temp = "#{source}.rot-#{System.unique_integer([:positive])}#{Path.extname(source)}"

    with {:ok, image} <- Image.open(source),
         {:ok, {upright, _flags}} <- Image.autorotate(image),
         {:ok, rotated} <- Image.rotate(upright, degrees),
         {:ok, _} <- Image.write(rotated, temp, quality: 90),
         :ok <- File.rename(temp, source) do
      flush_vips_cache()
      purge_variants(upload)
      store_rotation(upload, source, degrees)
    else
      _ ->
        File.rm(temp)
        {:error, :rotate_failed}
    end
  end

  # The rename above is the point of no return, so nothing in here may raise: read the
  # new size defensively and keep the old one if the stat fails.
  # sobelow_skip ["Traversal.FileModule"]
  # source is the app-derived path from do_rotate/2 above.
  defp store_rotation(%Upload{} = upload, source, degrees) do
    {focal_x, focal_y} = rotate_focal(upload.focal_point_x, upload.focal_point_y, degrees)

    # Keep the old values if the file cannot be read back rather than storing nils —
    # templates size their aspect boxes from these.
    {width, height} =
      case dimensions(source) do
        {nil, nil} -> {upload.width, upload.height}
        dimensions -> dimensions
      end

    byte_size =
      case File.stat(source) do
        {:ok, %File.Stat{size: size}} -> size
        _ -> upload.byte_size
      end

    upload
    |> Ecto.Changeset.change(%{
      width: width,
      height: height,
      byte_size: byte_size,
      focal_point_x: focal_x,
      focal_point_y: focal_y,
      revision: upload.revision + 1
    })
    |> Repo.update()
  end

  # libvips memoizes operations by their arguments — the source *filename* among them —
  # and has no idea the bytes underneath changed. The consumer that needs this is
  # `dimensions/1` in store_rotation/3: without the flush its `Image.open` returns the
  # pre-rotation size, and we store the wrong width/height. Variant generation is *not*
  # at risk (measured): `Image.thumbnail` on a path uses a sequential-access loader, which
  # libvips marks non-cacheable, so it always reads the file. Setting the limit to 0 trims
  # the cache; the previous limit is restored right after, so this costs a cold cache once
  # per rotation, nothing more.
  defp flush_vips_cache do
    max = Vix.Vips.cache_get_max()
    :ok = Vix.Vips.cache_set_max(0)
    :ok = Vix.Vips.cache_set_max(max)
  end

  # Where the focal point ends up after the image turns under it. Rounded like the
  # fractions on media URLs (BbhWeb.Format), so repeated turns can't drift.
  defp rotate_focal(x, y, degrees) when is_number(x) and is_number(y) do
    case degrees do
      90 -> {frac(1.0 - y), frac(x)}
      180 -> {frac(1.0 - x), frac(1.0 - y)}
      270 -> {frac(y), frac(1.0 - x)}
    end
  end

  defp rotate_focal(_x, _y, _degrees), do: {nil, nil}

  defp frac(value), do: Float.round(value * 1.0, 4)

  @doc """
  Drop every cached variant of one upload.

  Variants live in a per-upload directory (named after a hash of the storage key)
  precisely so they can be discarded as a unit: their file names are content hashes of
  the requested size, so there is no other way to find them all. Called after a
  rotation and when the upload is deleted.
  """
  # sobelow_skip ["Traversal.FileModule"]
  # The path is media_cache_dir/<hex sha256> — no user input reaches it.
  def purge_variants(%Upload{storage_key: key}), do: File.rm_rf(variant_dir(key))

  defp variant_dir(key), do: Path.join(cache_dir(), hash(key))

  defp hash(value), do: :crypto.hash(:sha256, value) |> Base.encode16(case: :lower)

  ## Folders

  # Editor order first, name only to break ties between folders that have never been
  # dragged (they all sit at the position the migration gave them).
  @folder_order [asc: :position, asc: :name]

  @doc "Top-level folders (parent_id nil), in editor order, with their sub-folders preloaded."
  def list_root_folders do
    children = from(c in Folder, order_by: ^@folder_order)

    Repo.all(
      from f in Folder,
        where: is_nil(f.parent_id),
        order_by: ^@folder_order,
        preload: [children: ^children]
    )
  end

  @doc """
  The whole folder tree in one go, for the media library's permanent tree view:
  root folders with their children (both in editor order) plus the file counts
  shown on every node.

  A count is the number the node actually lists when clicked, which since the branch
  scope means a parent counts its sub-folders' files too. `counts` holds every folder,
  `unfiled` the files in none. One grouped query covers the lot; per-node counting
  would be N+1.
  """
  def list_folder_tree do
    direct =
      Repo.all(from u in Upload, group_by: u.folder_id, select: {u.folder_id, count(u.id)})
      |> Map.new()

    roots = list_root_folders()

    %{
      roots: roots,
      counts: branch_counts(roots, direct),
      # From the direct counts, so folding the branches cannot count a parent twice.
      total: direct |> Map.values() |> Enum.sum(),
      unfiled: Map.get(direct, nil, 0)
    }
  end

  defp branch_counts(roots, direct) do
    Enum.reduce(roots, %{}, fn root, acc ->
      children = Map.new(root.children, &{&1.id, Map.get(direct, &1.id, 0)})
      own = Map.get(direct, root.id, 0)

      acc
      |> Map.merge(children)
      |> Map.put(root.id, own + (children |> Map.values() |> Enum.sum()))
    end)
  end

  @doc """
  A flat, indented `{label, value}` option list of all folders (plus a "no folder"
  entry) for a folder-select. Value `""` means the root.

  Takes already-loaded roots when the caller has them — the media library renders the
  tree and this select from the same data, and re-querying would double the preload on
  every folder change, upload, edit and drop.
  """
  def folder_options(roots \\ list_root_folders()) do
    [{"— Kein Ordner —", ""}] ++
      Enum.flat_map(roots, fn root ->
        [{root.name, root.id}] ++
          Enum.map(root.children, fn child -> {"#{root.name} / #{child.name}", child.id} end)
      end)
  end

  @doc """
  The sub-folders to offer while browsing `folder`: the root lists all top-level
  folders, a top-level folder lists its children, and a second-level folder has none
  (nesting is capped at two levels).
  """
  def child_folders(nil), do: list_subfolders(nil)
  def child_folders(%Folder{parent_id: nil, id: id}), do: list_subfolders(id)
  def child_folders(%Folder{}), do: []

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
  Fetch a folder by id, with its parent preloaded, or `nil`.

  The id reaches this straight from a URL query string and from drag & drop payloads,
  so anything that is not a UUID is a miss rather than an `Ecto.Query.CastError`.
  """
  def get_folder(id) do
    with {:ok, uuid} <- cast_uuid(id),
         %Folder{} = folder <- Repo.get(Folder, uuid) do
      Repo.preload(folder, :parent)
    else
      _ -> nil
    end
  end

  defp cast_uuid(id) when is_binary(id), do: Ecto.UUID.cast(id)
  defp cast_uuid(_id), do: :error

  def get_folder!(id), do: Repo.get!(Folder, id)

  def change_folder(%Folder{} = folder \\ %Folder{}, attrs \\ %{}),
    do: Folder.changeset(folder, attrs)

  @doc "Create a folder. `parent_id` nil = top level; nesting under a sub-folder is rejected."
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

        # Re-read under the lock rather than trusting a value read before it:
        # move_folder/3 may be turning this very folder into a sub-folder, and the
        # depth check has to see the outcome of that race, not the state before it.
        parent = parent_id && Repo.get(Folder, parent_id)

        %Folder{}
        |> Folder.changeset(attrs, parent)
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
  move the two-level cap forbids (`Folder.move_changeset/4`) leaves the tree untouched
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

        moved =
          locked
          |> Folder.move_changeset(
            %{parent_id: parent_id},
            parent_id && Repo.get(Folder, parent_id),
            children?(locked)
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

  defp children?(%Folder{id: id}), do: Repo.exists?(from f in Folder, where: f.parent_id == ^id)

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

  @doc """
  Where a media item is referenced. Returns a keyword list of `{place, count}` for
  every place with at least one reference; an empty list means it is safe to delete.
  """
  def usages(%Upload{id: id}) do
    counts = [
      articles: count_refs(Bbh.Content.ArticleImage, :media_id, id),
      media_cards: count_refs(Bbh.Content.Blocks.MediaCard, :image_id, id),
      galleries: count_refs(Bbh.Content.Blocks.GalleryFile, :media_id, id),
      # `people.portrait_id` nilifies on delete, so an unguarded delete would silently
      # empty the portrait on a person's card instead of refusing.
      portraits: count_refs(Bbh.Club.Person, :portrait_id, id)
    ]

    Enum.filter(counts, fn {_place, n} -> n > 0 end)
  end

  @doc "True when the media item is still referenced somewhere and must not be deleted."
  def in_use?(%Upload{} = upload), do: usages(upload) != []

  defp count_refs(schema, field, id) do
    Repo.aggregate(from(x in schema, where: field(x, ^field) == ^id), :count, :id)
  end

  @doc """
  Delete an upload record, its original file and its cached variants.
  Refuses with `{:error, :in_use}` while the media is still referenced by an article,
  media card, gallery, or a person's portrait.
  """
  # sobelow_skip ["Traversal.FileModule"]
  # Path is uploads_dir/<db storage_key>; storage_key is set only at creation and
  # format-validated (Upload.changeset), and is not user-updatable
  # (Upload.update_changeset) — so it can never contain "..".
  def delete_upload(%Upload{} = upload) do
    if in_use?(upload) do
      {:error, :in_use}
    else
      File.rm(Path.join(uploads_dir(), upload.storage_key))
      purge_variants(upload)
      Repo.delete(upload)
    end
  end

  @doc """
  Resolve a media request to a servable file. Returns `{:ok, path, content_type}`
  or `:error`. With no dimensions, serves the original; otherwise a cached WebP
  variant (`fit=cover` when both dimensions are given).

  `focal_x`/`focal_y` (fractions in `0.0..1.0`) shift a cover crop's window off
  center toward that point; `nil` keeps the default center crop.
  """
  def resolve_variant(key, width, height, focal_x \\ nil, focal_y \\ nil) do
    with {:ok, source} <- safe_source(key), true <- File.regular?(source) do
      type = content_type(source)

      # Non-images (PDFs, …) have no responsive variants — always serve the original.
      if (is_nil(width) and is_nil(height)) or not image_type?(type),
        do: {:ok, source, type},
        else: variant(source, key, width, height, focal(width, height, focal_x, focal_y))
    else
      _ -> :error
    end
  end

  # A focal point only affects a cover crop (both dimensions given). Otherwise it
  # is irrelevant, so drop it — keeps the cache key stable with the pre-focal path.
  defp focal(width, height, x, y)
       when is_integer(width) and is_integer(height) and is_number(x) and is_number(y),
       do: {clamp01(x), clamp01(y)}

  defp focal(_width, _height, _x, _y), do: nil

  defp clamp01(v) when v < 0.0, do: 0.0
  defp clamp01(v) when v > 1.0, do: 1.0
  defp clamp01(v), do: v * 1.0

  @doc """
  Copy a file into the uploads dir and create an `Upload` row (used by the admin
  media library and the one-time import). Extra `attrs` (title, copyright, …) are merged.

  The file's real type is sniffed from its magic bytes; anything that isn't a
  supported image is rejected with `{:error, :unsupported_media_type}`; an image
  whose pixel dimensions exceed the megapixel budget is rejected with
  `{:error, :image_too_large}`. The stored content type and storage-key extension
  come from the detected type, never from the client-supplied filename/content type.
  """
  def store_file(source_path, attrs \\ %{}) do
    case detect_image_type(source_path) do
      nil -> {:error, :unsupported_media_type}
      detected_type -> do_store_file(source_path, attrs, detected_type)
    end
  end

  # sobelow_skip ["Traversal.FileModule"]
  # dest is uploads_dir/<app-generated key>; source_path is a server-side temp file.
  defp do_store_file(source_path, attrs, detected_type) do
    # Read dimensions from the SOURCE (header-only, cheap) and reject a bomb
    # BEFORE copying it into the uploads dir or ever decoding its pixels.
    {width, height} = if image_type?(detected_type), do: dimensions(source_path), else: {nil, nil}

    if oversized?(width, height) do
      {:error, :image_too_large}
    else
      ext = Map.fetch!(@ext_for_type, detected_type)

      key = "#{Date.utc_today().year}/#{Ecto.UUID.generate()}#{ext}"
      dest = Path.join(uploads_dir(), key)
      File.mkdir_p!(Path.dirname(dest))
      File.cp!(source_path, dest)

      attrs
      |> Map.new(fn {k, v} -> {to_string(k), v} end)
      |> Map.merge(%{
        "storage_key" => key,
        "filename" => attrs[:filename] || attrs["filename"] || Path.basename(source_path),
        "content_type" => detected_type,
        "byte_size" => File.stat!(dest).size,
        "width" => width,
        "height" => height
      })
      |> then(&Upload.changeset(%Upload{}, &1))
      |> Repo.insert()
      |> tap_prewarm()
    end
  end

  defp oversized?(w, h) when is_integer(w) and is_integer(h), do: w * h > max_pixels()
  defp oversized?(_w, _h), do: false

  defp max_pixels, do: Application.get_env(:bbh, :max_image_pixels, @default_max_pixels)

  # Pre-generate the admin thumbnails off the request path so the upload response
  # stays snappy; generation still funnels through VariantLimiter (see variant/4).
  defp tap_prewarm({:ok, %Upload{} = upload} = result) do
    if image?(upload) and Application.get_env(:bbh, :media_prewarm, true) do
      Task.Supervisor.start_child(Bbh.TaskSupervisor, fn ->
        Enum.each(@prewarm_variants, fn {w, h} -> resolve_variant(upload.storage_key, w, h) end)
      end)
    end

    result
  end

  defp tap_prewarm(result), do: result

  # Sniff the real image type from the leading bytes. Returns a MIME string for
  # supported image types, or nil for anything unrecognized.
  # sobelow_skip ["Traversal.FileModule"]
  # path is a server-side temp/upload file, not a client-supplied path.
  defp detect_image_type(path) do
    case File.open(path, [:read, :binary], &IO.binread(&1, 512)) do
      {:ok, data} when is_binary(data) -> magic_type(data)
      _ -> nil
    end
  end

  defp magic_type(<<0xFF, 0xD8, 0xFF, _::binary>>), do: "image/jpeg"
  defp magic_type(<<0x89, "PNG\r\n", 0x1A, 0x0A, _::binary>>), do: "image/png"
  defp magic_type(<<"GIF87a", _::binary>>), do: "image/gif"
  defp magic_type(<<"GIF89a", _::binary>>), do: "image/gif"
  defp magic_type(<<"RIFF", _::binary-size(4), "WEBP", _::binary>>), do: "image/webp"
  defp magic_type(<<"%PDF-", _::binary>>), do: "application/pdf"

  defp magic_type(<<_::binary-size(4), "ftyp", brand::binary-size(4), _::binary>>)
       when brand in ["avif", "avis"],
       do: "image/avif"

  defp magic_type(data) when is_binary(data) do
    # SVG is text — accept only if the (whitespace-trimmed) start looks like SVG/XML.
    if String.valid?(data) do
      trimmed = data |> String.trim_leading() |> String.downcase()

      if String.starts_with?(trimmed, "<?xml") or String.starts_with?(trimmed, "<svg"),
        do: "image/svg+xml",
        else: nil
    end
  end

  defp variant(source, key, width, height, focal) do
    seed = key |> cache_seed(width, height, focal) |> revision_seed(revision_for(key))
    dest = Path.join(variant_dir(key), "#{hash(seed)}.webp")

    cond do
      File.regular?(dest) ->
        {:ok, dest, "image/webp"}

      limited_generate(source, dest, width, height, focal) == :ok ->
        {:ok, dest, "image/webp"}

      # On any processing failure, fall back to the original so the page still shows.
      true ->
        {:ok, source, content_type(source)}
    end
  end

  # The focal point is only folded into the key when it actually applies, so
  # existing (center-cropped) cache files stay valid for the common no-focal case.
  defp cache_seed(key, width, height, nil), do: "#{key}|#{width}|#{height}"
  defp cache_seed(key, width, height, {x, y}), do: "#{key}|#{width}|#{height}|#{x}|#{y}"

  # The revision joins the key so that after a rotation every earlier entry is
  # *unreachable*, not merely deleted. Purging alone is not enough: a generation already
  # in flight when the rotation purges the directory finishes afterwards and writes the
  # pre-rotation image back under the very name the next request looks up — and that
  # sideways thumbnail would then be served from disk forever. Only folded in once it is
  # non-zero, so every cache entry written before rotation existed stays valid.
  defp revision_seed(seed, 0), do: seed
  defp revision_seed(seed, revision), do: "#{seed}|r#{revision}"

  # Read from the database, never from the request: taking it from the client's `?v=`
  # would let anyone mint unbounded cache entries.
  defp revision_for(key) do
    Repo.one(from u in Upload, where: u.storage_key == ^key, select: u.revision) || 0
  end

  # Bound concurrent generation so a cold-cache burst (the media library/picker
  # requests one variant per image at once) can't pile up native image decodes.
  defp limited_generate(source, dest, width, height, focal) do
    Bbh.Media.VariantLimiter.run(fn -> generate(source, dest, width, height, focal) end)
  end

  # sobelow_skip ["Traversal.FileModule"]
  # source/dest are app-derived paths under uploads_dir (see variant/5 + safe_source/1).
  defp generate(source, dest, width, height, focal) do
    File.mkdir_p!(Path.dirname(dest))

    # Pass the source PATH (not an opened image) to Image.thumbnail so libvips
    # uses shrink-on-load / sequential access — it decodes a downscaled image
    # directly instead of first materializing the full-resolution pixel buffer.
    # This keeps peak memory at tens of MB even for very large source images.
    with {:ok, thumb} <- thumbnail(source, width, height, focal),
         {:ok, _} <- Image.write(thumb, dest, quality: 82) do
      :ok
    else
      _ -> :error
    end
  end

  defp thumbnail(source, width, nil, _focal), do: Image.thumbnail(source, width)
  defp thumbnail(source, nil, height, _focal), do: Image.thumbnail(source, "x#{height}")

  defp thumbnail(source, width, height, nil),
    do: Image.thumbnail(source, width, height: height, crop: :center)

  # Focal cover crop: scale the source so it just covers the box (shrink-on-load
  # from the path, same as the center path), then extract the target window
  # positioned around the focal point instead of the middle.
  defp thumbnail(source, width, height, {fx, fy}) do
    case dimensions(source) do
      {w0, h0} when is_integer(w0) and is_integer(h0) and w0 > 0 and h0 > 0 ->
        scale = max(width / w0, height / h0)
        sw = round(w0 * scale)
        sh = round(h0 * scale)
        left = crop_offset(fx, sw, width)
        top = crop_offset(fy, sh, height)

        with {:ok, cover} <- Image.thumbnail(source, "#{sw}x#{sh}", crop: :none) do
          Image.crop(cover, left, top, width, height)
        end

      # Dimensions unreadable — fall back to a center crop rather than failing.
      _ ->
        Image.thumbnail(source, width, height: height, crop: :center)
    end
  end

  # Top-left of a `size`-wide window centered on fraction `f` of `full`, clamped
  # so the window stays inside the scaled image.
  defp crop_offset(f, full, size) do
    round(f * full - size / 2) |> min(full - size) |> max(0)
  end

  defp dimensions(path) do
    case Image.open(path) do
      {:ok, img} -> {Image.width(img), Image.height(img)}
      _ -> {nil, nil}
    end
  end

  # Reject path traversal; keys are relative to the uploads dir.
  defp safe_source(key) do
    if String.contains?(key, ".."), do: :error, else: {:ok, Path.join(uploads_dir(), key)}
  end

  defp content_type(path),
    do:
      Map.get(
        @content_types,
        path |> Path.extname() |> String.downcase(),
        "application/octet-stream"
      )
end
