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

  @doc "True for a stored content type we treat as a displayable image (not a PDF/document)."
  def image_type?(type), do: type in @image_types

  @doc "True if the upload is a displayable image (has an image thumbnail)."
  def image?(%Upload{content_type: type}), do: image_type?(type)

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

  def update_upload(%Upload{} = upload, attrs),
    do: upload |> Upload.update_changeset(attrs) |> Repo.update()

  @doc "Move an upload into a folder (`nil` moves it back to the unfiled/root level)."
  def move_upload(%Upload{} = upload, folder_id),
    do: upload |> Upload.update_changeset(%{folder_id: folder_id}) |> Repo.update()

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
  Delete an upload record and its original file (variant cache is regenerable).
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
      Repo.delete(upload)
    end
  end

  @doc """
  Resolve a media request to a servable file. Returns `{:ok, path, content_type}`
  or `:error`. With no dimensions, serves the original; otherwise a cached WebP
  variant (`fit=cover` when both dimensions are given).
  """
  def resolve_variant(key, width, height) do
    with {:ok, source} <- safe_source(key), true <- File.regular?(source) do
      type = content_type(source)

      # Non-images (PDFs, …) have no responsive variants — always serve the original.
      if (is_nil(width) and is_nil(height)) or not image_type?(type),
        do: {:ok, source, type},
        else: variant(source, key, width, height)
    else
      _ -> :error
    end
  end

  @doc """
  Copy a file into the uploads dir and create an `Upload` row (used by the admin
  media library and the one-time import). Extra `attrs` (title, copyright, …) are merged.

  The file's real type is sniffed from its magic bytes; anything that isn't a
  supported image is rejected with `{:error, :unsupported_media_type}`. The stored
  content type and storage-key extension come from the detected type, never from
  the client-supplied filename/content type.
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
    ext = Map.fetch!(@ext_for_type, detected_type)

    key = "#{Date.utc_today().year}/#{Ecto.UUID.generate()}#{ext}"
    dest = Path.join(uploads_dir(), key)
    File.mkdir_p!(Path.dirname(dest))
    File.cp!(source_path, dest)

    {width, height} = if image_type?(detected_type), do: dimensions(dest), else: {nil, nil}

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
  end

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

  defp variant(source, key, width, height) do
    name = :crypto.hash(:sha256, "#{key}|#{width}|#{height}") |> Base.encode16(case: :lower)
    dest = Path.join(cache_dir(), "#{name}.webp")

    cond do
      File.regular?(dest) ->
        {:ok, dest, "image/webp"}

      generate(source, dest, width, height) == :ok ->
        {:ok, dest, "image/webp"}

      # On any processing failure, fall back to the original so the page still shows.
      true ->
        {:ok, source, content_type(source)}
    end
  end

  # sobelow_skip ["Traversal.FileModule"]
  # source/dest are app-derived paths under uploads_dir (see variant/4 + safe_source/1).
  defp generate(source, dest, width, height) do
    File.mkdir_p!(Path.dirname(dest))

    with {:ok, img} <- Image.open(source),
         {:ok, thumb} <- thumbnail(img, width, height),
         {:ok, _} <- Image.write(thumb, dest, quality: 82) do
      :ok
    else
      _ -> :error
    end
  end

  defp thumbnail(img, width, nil), do: Image.thumbnail(img, width)
  defp thumbnail(img, nil, height), do: Image.thumbnail(img, "x#{height}")

  defp thumbnail(img, width, height),
    do: Image.thumbnail(img, width, height: height, crop: :center)

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
