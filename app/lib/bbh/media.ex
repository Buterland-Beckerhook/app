defmodule Bbh.Media do
  @moduledoc """
  Media storage and on-demand responsive variants (libvips via `Image`).

  Originals live under `:uploads_dir` keyed by `storage_key`. Requesting a size
  produces a cached WebP variant under `:media_cache_dir` (regenerable, so it is
  excluded from backups). Replaces Directus asset transforms.
  """
  import Ecto.Query
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
  (`:root` = unfiled, a folder id, or absent = all), `:images_only`, and `:sort`.
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

  defp filter_folder(query, folder_id), do: where(query, [u], u.folder_id == ^folder_id)

  defp filter_images_only(query, true), do: where(query, [u], u.content_type in ^@image_types)
  defp filter_images_only(query, _), do: query

  defp sort_uploads(query, "oldest"), do: from(u in query, order_by: [asc: u.inserted_at])
  defp sort_uploads(query, "name"), do: from(u in query, order_by: [asc: u.filename])
  defp sort_uploads(query, _newest), do: from(u in query, order_by: [desc: u.inserted_at])
  def get_upload!(id), do: Repo.get!(Upload, id)

  def change_upload(%Upload{} = upload, attrs \\ %{}), do: Upload.update_changeset(upload, attrs)

  # Reindexed like the content writers in Bbh.Content: a gallery block's searchable text
  # is now the caption/title of its media items, so editing one here changes what the
  # site search should find.
  def update_upload(%Upload{} = upload, attrs),
    do: upload |> Upload.update_changeset(attrs) |> Repo.update() |> Bbh.Search.reindex_after()

  @doc "Move an upload into a folder (`nil` moves it back to the unfiled/root level)."
  def move_upload(%Upload{} = upload, folder_id),
    do: upload |> Upload.update_changeset(%{folder_id: folder_id}) |> Repo.update()

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

  @doc "Top-level folders (parent_id nil), alphabetical, with their sub-folders preloaded."
  def list_root_folders do
    children = from(c in Folder, order_by: [asc: c.name])

    Repo.all(
      from f in Folder,
        where: is_nil(f.parent_id),
        order_by: [asc: f.name],
        preload: [children: ^children]
    )
  end

  @doc """
  A flat, indented `{label, value}` option list of all folders (plus a "no folder"
  entry) for a folder-select. Value `""` means the root.
  """
  def folder_options do
    [{"— Kein Ordner —", ""}] ++
      Enum.flat_map(list_root_folders(), fn root ->
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

  @doc "Direct sub-folders of `parent_id` (nil = top level), alphabetical."
  def list_subfolders(nil),
    do: Repo.all(from f in Folder, where: is_nil(f.parent_id), order_by: [asc: f.name])

  def list_subfolders(parent_id),
    do: Repo.all(from f in Folder, where: f.parent_id == ^parent_id, order_by: [asc: f.name])

  def get_folder(nil), do: nil
  def get_folder(id), do: Repo.get(Folder, id) |> Repo.preload(:parent)

  def get_folder!(id), do: Repo.get!(Folder, id)

  def change_folder(%Folder{} = folder \\ %Folder{}, attrs \\ %{}),
    do: Folder.changeset(folder, attrs)

  @doc "Create a folder. `parent_id` nil = top level; nesting under a sub-folder is rejected."
  def create_folder(attrs) do
    parent = get_folder(attrs["parent_id"] || attrs[:parent_id])
    %Folder{} |> Folder.changeset(attrs, parent) |> Repo.insert()
  end

  def rename_folder(%Folder{} = folder, name),
    do: folder |> Folder.changeset(%{name: name}) |> Repo.update()

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
      galleries: count_refs(Bbh.Content.Blocks.GalleryFile, :media_id, id)
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
  media card, or gallery.
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
